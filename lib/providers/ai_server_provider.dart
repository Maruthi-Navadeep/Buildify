import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/ai_server_models.dart';
import '../services/native_server_bridge.dart';
import '../services/server_bridge_factory.dart';
import '../services/mdns_service.dart';
import '../backend/embedded_backend.dart';

const _catalogRemoteUrl =
    'https://raw.githubusercontent.com/Sujith8257/Buildify/main/assets/models/catalog.json';

final aiServerProvider =
    StateNotifierProvider<AiServerController, AiServerState>((ref) {
  return AiServerController();
});

final embeddedBackendProvider = Provider<EmbeddedBackendService>((ref) {
  final service = EmbeddedBackendService();
  ref.onDispose(() => service.dispose());
  return service;
});

final backendProjectsProvider = StreamProvider<List<BackendProject>>((ref) {
  final service = ref.watch(embeddedBackendProvider);
  return service.stream.map((state) => state.projects).distinct();
});

final backendStateProvider = StreamProvider<BackendState>((ref) {
  final service = ref.watch(embeddedBackendProvider);
  return service.stream;
});

class AiServerController extends StateNotifier<AiServerState> {
  AiServerController()
      : super(
          AiServerState(
            models: const [],
            downloads: {},
            device: const DeviceSnapshot(
              ramGb: 8,
              availRamGb: 4.0,
              freeStorageGb: 43.6,
              batteryPercent: 72,
              batteryCharging: false,
              ipAddress: '192.168.0.121',
              tailscaleIp: null,
              cpuLabel: '8-core ARM',
            ),
            selectedModelId: '',
            status: ServerStatus.stopped,
            port: 8080,
            requestCount: 0,
            requestsPerSecond: 0,
            uptime: Duration.zero,
            lowPowerMode: false,
            temperature: 0.7,
            tokenLimit: 100,
            logs: [
              ServerLog(
                'runtime ready: waiting for model selection',
                LogType.system,
              ),
            ],
            chat: const [],
            security: SecuritySettings.empty,
            tunnel: const TunnelState(status: TunnelStatus.stopped),
          ),
        ) {
    unawaited(_loadCatalogAndHydrate());
  }

  static List<ModelProfile> _parseCatalog(String jsonStr) {
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = decoded['models'] as List<dynamic>;
    return list
        .map((e) => ModelProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _loadCatalogAndHydrate() async {
    List<ModelProfile> catalog;
    try {
      final bundled = await rootBundle.loadString(
        'assets/models/catalog.json',
      );
      catalog = _parseCatalog(bundled);
    } catch (e) {
      catalog = const [];
    }
    if (catalog.isEmpty) {
      _appendLog('no bundled model catalog found', LogType.warning);
    }
    final downloads = <String, ModelDownload>{};
    for (final model in catalog) {
      downloads[model.id] = const ModelDownload(
        status: ModelDownloadStatus.notDownloaded,
        progress: 0,
      );
    }
    final savedModelId = await _secure.read(key: _kSecSelectedModelId);
    final initialModelId = (savedModelId != null &&
            savedModelId.isNotEmpty &&
            catalog.any((m) => m.id == savedModelId))
        ? savedModelId
        : (catalog.isEmpty ? '' : catalog.first.id);

    state = state.copyWith(
      models: catalog,
      selectedModelId: initialModelId,
      downloads: downloads,
    );
    _appendLog('loaded ${catalog.length} model(s) from catalog', LogType.system);
    unawaited(_loadCustomModels());
    unawaited(_hydrateNativeState());
    unawaited(_loadSecuritySettings());
  }

  final _discoveryBeacon = BuildifyDiscoveryBeacon();

  Future<void> refreshCatalog() async {
    try {
      final resp = await http
          .get(Uri.parse(_catalogRemoteUrl))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        _appendLog(
          'catalog update failed: HTTP ${resp.statusCode}',
          LogType.warning,
        );
        return;
      }
      final catalog = _parseCatalog(resp.body);
      if (catalog.isEmpty) {
        _appendLog('catalog update: remote catalog is empty', LogType.warning);
        return;
      }
      final downloads = <String, ModelDownload>{};
      for (final model in catalog) {
        final existing = state.downloads[model.id];
        if (existing != null) {
          downloads[model.id] = existing;
        } else {
          downloads[model.id] = const ModelDownload(
            status: ModelDownloadStatus.notDownloaded,
            progress: 0,
          );
        }
      }
      final savedModelId = await _secure.read(key: _kSecSelectedModelId);
      final selectedId = (savedModelId != null &&
              savedModelId.isNotEmpty &&
              catalog.any((m) => m.id == savedModelId))
          ? savedModelId
          : (state.selectedModelId.isNotEmpty &&
                  catalog.any((m) => m.id == state.selectedModelId)
              ? state.selectedModelId
              : catalog.first.id);
      state = state.copyWith(
        models: catalog,
        selectedModelId: selectedId,
        downloads: downloads,
      );
      _appendLog('catalog updated: ${catalog.length} model(s)', LogType.system);
      await _scanExistingModels();
    } catch (e) {
      _appendLog('catalog update failed: $e', LogType.warning);
    }
  }

  Timer? _uptimeTimer;
  Timer? _metricsTimer;
  DateTime? _startedAt;
  final ServerBridge _native = createServerBridge();
  String? _modelBasePath;
  final Map<String, http.Client> _downloadClients = {};
  final Map<String, StreamSubscription<List<int>>> _downloadSubs = {};
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kSecRequire = 'sec_require_api_key';
  static const _kSecApiKey = 'sec_api_key';
  static const _kSecIdleMinutes = 'sec_idle_minutes';
  static const _kSecBatteryPct = 'sec_battery_pct';
  static const _kSecThermal = 'sec_thermal_stop';
  static const _kSecSelectedModelId = 'sec_selected_model_id';

  // Returns the currently-selected model, falling back to the first available
  // model if the stored id is stale, and to a blank placeholder if the catalog
  // has not loaded yet. Callers that start the server guard against the blank
  // placeholder via the download-status check.
  static final _blankModel = ModelProfile(
    id: '', name: '', fileName: '', downloadUrl: '',
    sizeLabel: '', speed: '', quality: '', requiredRamGb: 0, description: '',
  );

  ModelProfile get selectedModel {
    if (state.models.isEmpty) return _blankModel;
    return state.models.firstWhere(
      (model) => model.id == state.selectedModelId,
      orElse: () => state.models.first,
    );
  }

  String get apiBaseUrl => 'http://${state.device.ipAddress}:${state.port}';

  Future<void> _hydrateNativeState() async {
    final ip = await _native.getLocalIp();
    final tailscaleIp = await _native.getTailscaleIp();
    final base = await _native.getModelBasePath();
    if (base != null && base.isNotEmpty) {
      _modelBasePath = base;
    }
    final status = await _native.getServerStatus();
    if (status != null) {
      state = state.copyWith(
        port: status.port,
        status: _statusFromNative(status.status),
        device: state.device.copyWith(
          ipAddress: ip ?? state.device.ipAddress,
          tailscaleIp: tailscaleIp,
          clearTailscaleIp: tailscaleIp == null,
        ),
      );
      _appendLog(
        'native bridge ready: ${status.status} on ${state.device.ipAddress}:${status.port}',
        LogType.system,
      );
      if (tailscaleIp != null) {
        _appendLog('tailscale detected: $tailscaleIp', LogType.system);
      }
      if (status.lastError != null && status.lastError!.isNotEmpty) {
        _appendLog('native: ${status.lastError}', LogType.warning);
      }
    } else {
      state = state.copyWith(
        device: state.device.copyWith(
          ipAddress: ip ?? state.device.ipAddress,
          tailscaleIp: tailscaleIp,
          clearTailscaleIp: tailscaleIp == null,
        ),
      );
    }
    await _scanExistingModels();
    _refreshMetrics();
    _metricsTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refreshMetrics());
  }

  void _refreshMetrics() {
    _native.getDeviceMetrics().then((metrics) {
      if (metrics == null) return;
      state = state.copyWith(
        device: state.device.copyWith(
          ramGb: (metrics['ramGb'] as num?)?.toInt() ?? state.device.ramGb,
          availRamGb: (metrics['availRamGb'] as num?)?.toDouble() ?? state.device.availRamGb,
          freeStorageGb: (metrics['freeStorageGb'] as num?)?.toDouble() ?? state.device.freeStorageGb,
          batteryPercent: (metrics['batteryPercent'] as num?)?.toInt() ?? state.device.batteryPercent,
          batteryCharging: (metrics['batteryCharging'] as bool?) ?? state.device.batteryCharging,
          cpuLabel: (metrics['cpuLabel'] as String?) ?? state.device.cpuLabel,
        ),
      );
    });
  }

  Future<void> _loadSecuritySettings() async {
    try {
      final require = (await _secure.read(key: _kSecRequire)) == '1';
      var key = (await _secure.read(key: _kSecApiKey)) ?? '';
      if (key.isEmpty) {
        key = _generateApiKey();
        await _secure.write(key: _kSecApiKey, value: key);
      }
      final idle =
          int.tryParse((await _secure.read(key: _kSecIdleMinutes)) ?? '') ?? 0;
      final battery =
          int.tryParse((await _secure.read(key: _kSecBatteryPct)) ?? '') ?? 0;
      final thermal = (await _secure.read(key: _kSecThermal)) != '0';
      state = state.copyWith(
        security: SecuritySettings(
          requireApiKey: require,
          apiKey: key,
          idleTimeoutMinutes: idle,
          batteryStopPercent: battery,
          thermalStop: thermal,
        ),
      );
      _appendLog(
        'security loaded: '
        'apiKey=${require ? "required" : "off"}, '
        'idle=${idle == 0 ? "off" : "${idle}m"}, '
        'battery=${battery == 0 ? "off" : "$battery%"}, '
        'thermal=${thermal ? "on" : "off"}',
        LogType.system,
      );
    } catch (e) {
      _appendLog('security load failed: $e', LogType.warning);
    }
  }

  String _generateApiKey() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    final buf = StringBuffer('bk_');
    for (var i = 0; i < 32; i++) {
      buf.write(chars[r.nextInt(chars.length)]);
    }
    return buf.toString();
  }

  Future<void> setRequireApiKey(bool value) async {
    state = state.copyWith(security: state.security.copyWith(requireApiKey: value));
    await _secure.write(key: _kSecRequire, value: value ? '1' : '0');
    _appendLog(
      value ? 'api key required for incoming requests' : 'api key disabled',
      LogType.system,
    );
    if (state.status == ServerStatus.running) {
      _appendLog(
        'restart the server to apply api key change',
        LogType.warning,
      );
    }
  }

  Future<void> regenerateApiKey() async {
    final next = _generateApiKey();
    state = state.copyWith(security: state.security.copyWith(apiKey: next));
    await _secure.write(key: _kSecApiKey, value: next);
    _appendLog('new api key generated', LogType.system);
    if (state.status == ServerStatus.running && state.security.requireApiKey) {
      _appendLog('restart the server to apply new key', LogType.warning);
    }
  }

  Future<void> setIdleTimeoutMinutes(int minutes) async {
    final clamped = minutes.clamp(0, 240);
    state = state.copyWith(
      security: state.security.copyWith(idleTimeoutMinutes: clamped),
    );
    await _secure.write(key: _kSecIdleMinutes, value: '$clamped');
  }

  Future<void> setBatteryStopPercent(int pct) async {
    final clamped = pct.clamp(0, 80);
    state = state.copyWith(
      security: state.security.copyWith(batteryStopPercent: clamped),
    );
    await _secure.write(key: _kSecBatteryPct, value: '$clamped');
  }

  Future<void> setThermalStop(bool value) async {
    state = state.copyWith(security: state.security.copyWith(thermalStop: value));
    await _secure.write(key: _kSecThermal, value: value ? '1' : '0');
  }

  Future<void> _scanExistingModels() async {
    final base = _modelBasePath;
    if (base == null || base.isEmpty) return;
    final dir = Directory(base);
    if (!await dir.exists()) return;
    final downloads = {...state.downloads};
    var found = 0;
    for (final m in state.models) {
      final f = File('$base/${m.fileName}');
      if (await f.exists() && (await f.length()) > 1024 * 1024) {
        downloads[m.id] = const ModelDownload(
          status: ModelDownloadStatus.downloaded,
          progress: 1,
        );
        found++;
      }
    }
    if (found > 0) {
      state = state.copyWith(downloads: downloads);
      _appendLog(
        'detected $found existing model file(s) in $base',
        LogType.system,
      );
    }
  }

  void selectModel(String modelId) {
    if (state.status == ServerStatus.running) {
      _appendLog('stop the server before switching models', LogType.warning);
      return;
    }
    state = state.copyWith(selectedModelId: modelId);
    unawaited(_secure.write(key: _kSecSelectedModelId, value: modelId));
    _appendLog('selected model: ${selectedModel.name}', LogType.system);
  }

  Future<void> downloadModel(String modelId) async {
    final current = state.downloads[modelId];
    if (current == null ||
        current.status == ModelDownloadStatus.downloaded ||
        current.status == ModelDownloadStatus.downloading) {
      return;
    }
    final model = state.models.firstWhere((m) => m.id == modelId);

    _modelBasePath ??= await _native.getModelBasePath();
    final base = _modelBasePath;
    if (base == null || base.isEmpty) {
      _appendLog('cannot resolve models directory', LogType.warning);
      return;
    }
    await Directory(base).create(recursive: true);

    final target = File('$base/${model.fileName}');
    if (await target.exists() && (await target.length()) > 1024 * 1024) {
      _setDownload(
        modelId,
        const ModelDownload(
          status: ModelDownloadStatus.downloaded,
          progress: 1,
        ),
      );
      _appendLog('already present: ${model.name}', LogType.system);
      return;
    }
    final part = File('${target.path}.part');
    // Keep existing .part for resume; only delete if the final file already exists
    // but wasn't detected as downloaded (size check failed).
    final existingBytes =
        await part.exists() ? await part.length() : 0;

    _setDownload(
      modelId,
      const ModelDownload(
        status: ModelDownloadStatus.downloading,
        progress: 0.0,
      ),
    );
    _appendLog(
      existingBytes > 0
          ? 'resuming download: ${model.name} (${_fmtBytes(existingBytes)} already fetched)'
          : 'download started: ${model.name}',
      LogType.system,
    );

    final client = http.Client();
    _downloadClients[modelId] = client;

    http.StreamedResponse resp;
    try {
      final req = http.Request('GET', Uri.parse(model.downloadUrl));
      req.followRedirects = true;
      if (existingBytes > 0) {
        req.headers['Range'] = 'bytes=$existingBytes-';
      }
      resp = await client.send(req);
    } catch (e) {
      _downloadClients.remove(modelId)?.close();
      _setDownload(
        modelId,
        const ModelDownload(
          status: ModelDownloadStatus.notDownloaded,
          progress: 0,
        ),
      );
      _appendLog('download failed: $e', LogType.warning);
      return;
    }

    // 206 = resume accepted, 200 = server sent full file (no range support)
    final isResume = resp.statusCode == 206;
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      _downloadClients.remove(modelId)?.close();
      _setDownload(
        modelId,
        const ModelDownload(
          status: ModelDownloadStatus.notDownloaded,
          progress: 0,
        ),
      );
      _appendLog(
        'download error HTTP ${resp.statusCode} for ${model.name}',
        LogType.warning,
      );
      return;
    }

    // If server ignored Range and sent 200, discard any partial data
    if (!isResume && existingBytes > 0) {
      try {
        await part.delete();
      } catch (_) {}
    }

    final contentLength = resp.contentLength ?? 0;
    final total = isResume ? existingBytes + contentLength : contentLength;
    final sink = isResume
        ? part.openWrite(mode: FileMode.append)
        : part.openWrite();
    var received = isResume ? existingBytes : 0;
    var lastReportedProgress = total > 0 ? received / total : -1.0;

    final completer = Completer<void>();
    final sub = resp.stream.listen(
      (chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final progress = (received / total).clamp(0.0, 1.0);
          if (progress - lastReportedProgress >= 0.005) {
            lastReportedProgress = progress;
            _setDownload(
              modelId,
              ModelDownload(
                status: ModelDownloadStatus.downloading,
                progress: progress,
              ),
            );
          }
        }
      },
      onDone: () async {
        try {
          await sink.flush();
          await sink.close();
          await part.rename(target.path);
          _setDownload(
            modelId,
            const ModelDownload(
              status: ModelDownloadStatus.downloaded,
              progress: 1,
            ),
          );
          state = state.copyWith(selectedModelId: modelId);
          _appendLog('model ready: ${model.name}', LogType.system);
        } catch (e) {
          _appendLog('finalize failed: $e', LogType.warning);
          _setDownload(
            modelId,
            const ModelDownload(
              status: ModelDownloadStatus.notDownloaded,
              progress: 0,
            ),
          );
        } finally {
          _downloadClients.remove(modelId)?.close();
          _downloadSubs.remove(modelId);
          if (!completer.isCompleted) completer.complete();
        }
      },
      onError: (Object e) async {
        try {
          await sink.close();
        } catch (_) {}
        try {
          if (await part.exists()) await part.delete();
        } catch (_) {}
        _setDownload(
          modelId,
          const ModelDownload(
            status: ModelDownloadStatus.notDownloaded,
            progress: 0,
          ),
        );
        _appendLog('download failed: $e', LogType.warning);
        _downloadClients.remove(modelId)?.close();
        _downloadSubs.remove(modelId);
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    _downloadSubs[modelId] = sub;
    await completer.future;
  }

  Future<void> cancelDownload(String modelId) async {
    final sub = _downloadSubs.remove(modelId);
    final client = _downloadClients.remove(modelId);
    try {
      await sub?.cancel();
    } catch (_) {}
    try {
      client?.close();
    } catch (_) {}
    final base = _modelBasePath;
    if (base != null) {
      final model = state.models.firstWhere(
        (m) => m.id == modelId,
        orElse: () => state.models.first,
      );
      final part = File('$base/${model.fileName}.part');
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
    _setDownload(
      modelId,
      const ModelDownload(
        status: ModelDownloadStatus.notDownloaded,
        progress: 0,
      ),
    );
    _appendLog('download canceled: ${_modelName(modelId)}', LogType.warning);
  }

  Future<void> startServer() async {
    if (state.status == ServerStatus.running ||
        state.status == ServerStatus.starting) {
      return;
    }
    final download = state.downloads[selectedModel.id];
    if (download?.status != ModelDownloadStatus.downloaded) {
      _appendLog(
        'download ${selectedModel.name} before starting',
        LogType.warning,
      );
      return;
    }
    state = state.copyWith(status: ServerStatus.starting);
    _appendLog('loading ${selectedModel.fileName}', LogType.system);
    _modelBasePath ??= await _native.getModelBasePath();
    final sec = state.security;
    final response = await _native.startServer(
      modelPath: _modelPathFor(selectedModel),
      port: state.port,
      apiKey: sec.requireApiKey ? sec.apiKey : null,
      idleMinutes: sec.idleTimeoutMinutes,
      batteryStopPercent: sec.batteryStopPercent,
      thermalStop: sec.thermalStop,
    );
    if (!response.ok) {
      state = state.copyWith(status: ServerStatus.stopped);
      _appendLog('native start failed: ${response.message}', LogType.warning);
      return;
    }

    final deadline = DateTime.now().add(const Duration(seconds: 45));
    NativeServerStatus? live;
    var sawStarting = false;
    var polls = 0;
    while (DateTime.now().isBefore(deadline)) {
      polls++;
      live = await _native.getServerStatus();
      if (live == null) break;
      if (live.status == 'running') break;
      if (live.status == 'starting') {
        sawStarting = true;
      }
      final err = live.lastError;
      if (live.status == 'stopped' &&
          (sawStarting || (err != null && err.isNotEmpty) || polls >= 8)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    live ??= await _native.getServerStatus();

    if (live == null || live.status != 'running') {
      state = state.copyWith(status: ServerStatus.stopped);
      final err = live?.lastError;
      _appendLog(
        err == null || err.isEmpty
            ? 'server failed to start (check binary, model path, logcat)'
            : err,
        LogType.warning,
      );
      return;
    }

    _startedAt = DateTime.now();
    _uptimeTimer?.cancel();
    var ticks = 0;
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final started = _startedAt;
      if (started == null || state.status != ServerStatus.running) return;
      state = state.copyWith(
        uptime: DateTime.now().difference(started),
        requestsPerSecond: state.requestsPerSecond * 0.6,
      );
      ticks++;
      if (ticks % 5 == 0) {
        final live = await _native.getServerStatus();
        if (live != null &&
            live.status == 'stopped' &&
            state.status == ServerStatus.running) {
          _uptimeTimer?.cancel();
          _discoveryBeacon.stop();
          _startedAt = null;
          state = state.copyWith(
            status: ServerStatus.stopped,
            uptime: Duration.zero,
            requestsPerSecond: 0,
          );
          final reason = live.stopReason;
          _appendLog(
            reason != null && reason.isNotEmpty
                ? 'auto-stop: $reason'
                : (live.lastError ?? 'server stopped unexpectedly'),
            LogType.warning,
          );
        }
      }
    });
    state = state.copyWith(
      status: ServerStatus.running,
      uptime: Duration.zero,
      port: live.port,
    );
    _appendLog('server running on $apiBaseUrl', LogType.system);
    // Start beacon without tunnel URL; it will be updated once the tunnel resolves.
    unawaited(_discoveryBeacon.start(serverPort: live.port, modelName: selectedModel.name));
  }

  /// Called from _pollTunnelStatus once the public URL is known — restarts the
  /// beacon so it advertises the tunnel URL to SDK peers.
  void _updateBeaconTunnelUrl(String? tunnelUrl) {
    if (!_discoveryBeacon.isRunning) return;
    _discoveryBeacon.stop();
    unawaited(_discoveryBeacon.start(
      serverPort: state.port,
      modelName: selectedModel.name,
      tunnelUrl: tunnelUrl,
    ));
  }

  Future<void> stopServer() async {
    if (state.status == ServerStatus.stopped ||
        state.status == ServerStatus.stopping) {
      return;
    }
    state = state.copyWith(status: ServerStatus.stopping);
    final response = await _native.stopServer();
    if (!response.ok) {
      state = state.copyWith(status: ServerStatus.running);
      _appendLog('native stop failed: ${response.message}', LogType.warning);
      return;
    }

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final live = await _native.getServerStatus();
      if (live == null || live.status == 'stopped') break;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    _uptimeTimer?.cancel();
    _discoveryBeacon.stop();
    _startedAt = null;
    state = state.copyWith(
      status: ServerStatus.stopped,
      uptime: Duration.zero,
      requestsPerSecond: 0,
    );
    _appendLog('server stopped', LogType.system);
  }

  Future<bool> startTunnel() async {
    if (state.tunnel.status == TunnelStatus.running ||
        state.tunnel.status == TunnelStatus.starting) {
      return false;
    }
    if (state.status != ServerStatus.running) {
      _appendLog('start the AI server before enabling tunnel', LogType.warning);
      return false;
    }
    state = state.copyWith(tunnel: const TunnelState(status: TunnelStatus.starting));
    _appendLog('starting cloudflare tunnel on port ${state.port}', LogType.system);
    final response = await _native.startTunnel(port: state.port);
    if (!response.ok) {
      state = state.copyWith(
        tunnel: TunnelState(status: TunnelStatus.failed, lastError: response.message),
      );
      _appendLog('tunnel start failed: ${response.message}', LogType.warning);
      return false;
    }
    _pollTunnelStatus();
    return true;
  }

  Future<void> stopTunnel() async {
    if (state.tunnel.status == TunnelStatus.stopped) return;
    state = state.copyWith(tunnel: const TunnelState(status: TunnelStatus.stopped));
    await _native.stopTunnel();
    _appendLog('cloudflare tunnel stopped', LogType.system);
  }

  void _pollTunnelStatus({int attempt = 0}) {
    const maxAttempts = 15; // 30 s ceiling at 2 s/poll
    if (attempt >= maxAttempts) {
      state = state.copyWith(
        tunnel: const TunnelState(
          status: TunnelStatus.failed,
          lastError: 'tunnel startup timed out',
        ),
      );
      _appendLog('tunnel startup timed out after ${maxAttempts * 2}s', LogType.warning);
      return;
    }
    Future.delayed(const Duration(seconds: 2), () async {
      final live = await _native.getTunnelStatus();
      if (live == null) {
        if (state.tunnel.status == TunnelStatus.starting) {
          state = state.copyWith(
            tunnel: const TunnelState(status: TunnelStatus.failed, lastError: 'no response from native'),
          );
        }
        return;
      }
      final newStatus = _tunnelStatusFromNative(live.status);
      state = state.copyWith(
        tunnel: TunnelState(
          status: newStatus,
          publicUrl: live.publicUrl,
          lastError: live.lastError,
        ),
      );
      if (newStatus == TunnelStatus.running && live.publicUrl != null) {
        _appendLog('tunnel active: ${live.publicUrl}', LogType.system);
        _updateBeaconTunnelUrl(live.publicUrl);
      } else if (newStatus == TunnelStatus.failed) {
        _appendLog(
          'tunnel failed: ${live.lastError ?? "unknown"}',
          LogType.warning,
        );
      } else if (newStatus == TunnelStatus.starting) {
        _pollTunnelStatus(attempt: attempt + 1);
      }
    });
  }

  TunnelStatus _tunnelStatusFromNative(String? nativeStatus) {
    return switch (nativeStatus) {
      'running' => TunnelStatus.running,
      'starting' => TunnelStatus.starting,
      'failed' => TunnelStatus.failed,
      _ => TunnelStatus.stopped,
    };
  }

  void setLowPowerMode(bool enabled) {
    state = state.copyWith(
      lowPowerMode: enabled,
      tokenLimit: enabled ? 64 : 100,
    );
    _appendLog(
      enabled ? 'low-power mode enabled' : 'low-power mode disabled',
      LogType.system,
    );
  }

  void setTemperature(double value) {
    state = state.copyWith(temperature: value);
  }

  void setTokenLimit(double value) {
    state = state.copyWith(tokenLimit: value.round());
  }

  Future<void> sendPrompt(String prompt) async {
    final cleaned = prompt.trim();
    if (cleaned.isEmpty) return;
    if (state.status != ServerStatus.running) {
      _appendLog('prompt rejected: server is offline', LogType.warning);
      return;
    }

    state = state.copyWith(
      chat: [
        ...state.chat,
        ChatMessage(text: cleaned, fromUser: true, createdAt: DateTime.now()),
      ],
      requestCount: state.requestCount + 1,
      requestsPerSecond: state.requestsPerSecond + 1,
    );

    final port = state.port;
    final maxTokens = state.tokenLimit;
    final temperature = state.temperature;
    final url = Uri.parse('http://127.0.0.1:$port/v1/chat/completions');
    final body = jsonEncode({
      'messages': [
        {'role': 'user', 'content': cleaned},
      ],
      'max_tokens': maxTokens,
      'temperature': temperature,
    });

    final stopwatch = Stopwatch()..start();
    String answer;
    final sec = state.security;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (sec.requireApiKey && sec.apiKey.isNotEmpty)
        'Authorization': 'Bearer ${sec.apiKey}',
    };
    try {
      final resp = await http
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 120));
      stopwatch.stop();

      if (resp.statusCode != 200) {
        _appendLog(
          'POST /v1/chat/completions ${resp.statusCode}',
          LogType.warning,
        );
        answer =
            'HTTP ${resp.statusCode}: '
            '${resp.body.isEmpty ? 'no body' : resp.body}';
      } else {
        _appendLog('POST /v1/chat/completions 200', LogType.request);
        answer = _extractAssistantText(resp.body, fallback: resp.body);
      }
    } on TimeoutException {
      stopwatch.stop();
      _appendLog('chat request timed out', LogType.warning);
      answer = 'Request timed out after 120s. Try a smaller prompt.';
    } catch (e) {
      stopwatch.stop();
      _appendLog('chat request failed: $e', LogType.warning);
      answer = 'Request failed: $e';
    }

    state = state.copyWith(
      chat: [
        ...state.chat,
        ChatMessage(text: answer, fromUser: false, createdAt: DateTime.now()),
      ],
    );
  }

  String _extractAssistantText(
    String responseBody, {
    required String fallback,
  }) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map<String, dynamic>) {
            final message = first['message'];
            if (message is Map<String, dynamic>) {
              final content = message['content'];
              if (content is String && content.trim().isNotEmpty) {
                return content.trim();
              }
            }
            final text = first['text'];
            if (text is String && text.trim().isNotEmpty) {
              return text.trim();
            }
          }
        }
        final content = decoded['content'];
        if (content is String && content.trim().isNotEmpty) {
          return content.trim();
        }
      }
    } catch (_) {}
    return fallback;
  }

  // ─── Custom model persistence ──────────────────────────────────────────────

  Future<File> get _customModelsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/custom_models.json');
  }

  Future<void> _loadCustomModels() async {
    try {
      final file = await _customModelsFile;
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      final custom = list
          .whereType<Map<String, dynamic>>()
          .map(ModelProfile.fromJson)
          .toList();
      if (custom.isEmpty) return;
      final merged = [...state.models];
      final existingIds = merged.map((m) => m.id).toSet();
      final downloads = {...state.downloads};
      for (final m in custom) {
        if (!existingIds.contains(m.id)) {
          merged.add(m);
          downloads[m.id] = const ModelDownload(
            status: ModelDownloadStatus.notDownloaded,
            progress: 0,
          );
        }
      }
      state = state.copyWith(models: merged, downloads: downloads);
    } catch (_) {}
  }

  Future<void> _saveCustomModels() async {
    try {
      final custom = state.models
          .where((m) => m.id.startsWith('custom_'))
          .map((m) => {
                'id': m.id,
                'name': m.name,
                'fileName': m.fileName,
                'downloadUrl': m.downloadUrl,
                'sizeLabel': m.sizeLabel,
                'speed': m.speed,
                'quality': m.quality,
                'requiredRamGb': m.requiredRamGb,
                'description': m.description,
              })
          .toList();
      final file = await _customModelsFile;
      await file.writeAsString(jsonEncode(custom));
    } catch (_) {}
  }

  // ─── Download from arbitrary URL ───────────────────────────────────────────

  /// Creates a custom [ModelProfile] and starts downloading it.
  Future<void> downloadFromUrl({
    required String downloadUrl,
    required String displayName,
    required String fileName,
    String sizeLabel = '',
    String description = '',
  }) async {
    final id =
        'custom_${fileName.replaceAll('.gguf', '').replaceAll(RegExp(r'[^a-z0-9]'), '_').toLowerCase()}';

    if (!state.models.any((m) => m.id == id)) {
      final profile = ModelProfile(
        id: id,
        name: displayName,
        fileName: fileName,
        downloadUrl: downloadUrl,
        sizeLabel: sizeLabel,
        speed: 'varies',
        quality: 'custom',
        requiredRamGb: 4,
        description: description.isNotEmpty
            ? description
            : 'Custom model: $displayName',
      );
      state = state.copyWith(
        models: [...state.models, profile],
        downloads: {
          ...state.downloads,
          id: const ModelDownload(
            status: ModelDownloadStatus.notDownloaded,
            progress: 0,
          ),
        },
      );
      await _saveCustomModels();
    }
    await downloadModel(id);
  }

  // ─── Local file import ──────────────────────────────────────────────────────

  /// Copies a local .gguf file into the models directory and registers it.
  Future<void> importLocalFile(String filePath) async {
    final source = File(filePath);
    if (!await source.exists()) {
      _appendLog('import failed: file not found', LogType.warning);
      return;
    }

    _modelBasePath ??= await _native.getModelBasePath();
    final base = _modelBasePath;
    if (base == null || base.isEmpty) {
      _appendLog('import failed: cannot resolve models directory',
          LogType.warning);
      return;
    }
    await Directory(base).create(recursive: true);

    final rawName = filePath.split('/').last.split('\\').last;
    final fileName = rawName.endsWith('.gguf') ? rawName : '$rawName.gguf';
    final id =
        'custom_${fileName.replaceAll('.gguf', '').replaceAll(RegExp(r'[^a-z0-9]'), '_').toLowerCase()}';
    final displayName = fileName
        .replaceAll('.gguf', '')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');

    final target = File('$base/$fileName');
    if (!await target.exists()) {
      _appendLog('copying model file…', LogType.system);
      await source.copy(target.path);
    }

    if (!state.models.any((m) => m.id == id)) {
      final fileSize = await target.length();
      final sizeLabel = fileSize >= 1024 * 1024 * 1024
          ? '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
          : '${(fileSize / (1024 * 1024)).round()} MB';
      final profile = ModelProfile(
        id: id,
        name: displayName,
        fileName: fileName,
        downloadUrl: '',
        sizeLabel: sizeLabel,
        speed: 'varies',
        quality: 'custom',
        requiredRamGb: 4,
        description: 'Locally imported model',
      );
      state = state.copyWith(
        models: [...state.models, profile],
        downloads: {
          ...state.downloads,
          id: const ModelDownload(
            status: ModelDownloadStatus.downloaded,
            progress: 1,
          ),
        },
      );
      await _saveCustomModels();
    } else {
      // Already registered — mark as downloaded
      final downloads = {...state.downloads};
      downloads[id] = const ModelDownload(
        status: ModelDownloadStatus.downloaded,
        progress: 1,
      );
      state = state.copyWith(downloads: downloads);
    }
    _appendLog('model imported: $displayName', LogType.system);
  }

  // ─── Delete model ───────────────────────────────────────────────────────────

  Future<void> deleteModel(String modelId) async {
    if (modelId == state.selectedModelId &&
        state.status == ServerStatus.running) {
      _appendLog('stop the server before deleting the active model',
          LogType.warning);
      return;
    }
    final model =
        state.models.firstWhere((m) => m.id == modelId, orElse: () => state.models.first);

    final base = _modelBasePath;
    if (base != null && base.isNotEmpty) {
      final file = File('$base/${model.fileName}');
      final part = File('${file.path}.part');
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
    }

    final isCustom = modelId.startsWith('custom_');
    final downloads = {...state.downloads}..remove(modelId);
    if (isCustom) {
      state = state.copyWith(
        models: state.models.where((m) => m.id != modelId).toList(),
        downloads: downloads,
      );
      await _saveCustomModels();
    } else {
      state = state.copyWith(
        downloads: {
          ...downloads,
          modelId: const ModelDownload(
            status: ModelDownloadStatus.notDownloaded,
            progress: 0,
          ),
        },
      );
    }
    _appendLog('model deleted: ${model.name}', LogType.system);
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  static String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).round()} MB';
  }

  @override
  void dispose() {
    for (final sub in _downloadSubs.values) {
      try {
        sub.cancel();
      } catch (_) {}
    }
    _downloadSubs.clear();
    for (final client in _downloadClients.values) {
      try {
        client.close();
      } catch (_) {}
    }
    _downloadClients.clear();
    _uptimeTimer?.cancel();
    _metricsTimer?.cancel();
    _discoveryBeacon.stop();
    super.dispose();
  }

  void _setDownload(String modelId, ModelDownload download) {
    state = state.copyWith(downloads: {...state.downloads, modelId: download});
  }

  void _appendLog(String message, LogType type) {
    final next = [...state.logs, ServerLog(message, type)];
    state = state.copyWith(
      logs: next.length > 80 ? next.sublist(next.length - 80) : next,
    );
  }

  String _modelName(String modelId) {
    final model = state.models.firstWhere(
      (m) => m.id == modelId,
      orElse: () => _blankModel,
    );
    return model.name.isNotEmpty ? model.name : modelId;
  }

  String _modelPathFor(ModelProfile model) {
    final base = _modelBasePath;
    if (base == null || base.isEmpty) {
      return model.fileName;
    }
    return '$base/${model.fileName}';
  }

  ServerStatus _statusFromNative(String? nativeStatus) {
    return switch (nativeStatus) {
      'running' => ServerStatus.running,
      'starting' => ServerStatus.starting,
      'stopping' => ServerStatus.stopping,
      _ => ServerStatus.stopped,
    };
  }
}
