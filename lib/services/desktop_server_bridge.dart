import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'native_server_bridge.dart';

/// Pure-Dart backend for desktop (Windows/Linux/macOS).
///
/// Desktop platforms have no MethodChannel implementation of `buildify.ai/server`,
/// but unlike iOS they *can* spawn processes — so we run the bundled
/// `llama-server` and `cloudflared` binaries directly via [Process.start].
///
/// Binary resolution order for each tool:
///   1. Env override — `BUILDIFY_LLAMA_SERVER` / `BUILDIFY_CLOUDFLARED`
///   2. `<dir of app executable>/native/<os>/<name>` and `<dir>/<name>`
///   3. bare name on PATH (runInShell)
class DesktopServerBridge implements ServerBridge {
  Process? _serverProc;
  int _serverPort = 8080;
  String? _serverError;

  Process? _tunnelProc;
  String? _tunnelUrl;
  String? _tunnelError;
  String _tunnelStatus = 'stopped';

  static final _osDir = Platform.isWindows
      ? 'windows'
      : (Platform.isMacOS ? 'macos' : 'linux');
  static String get _exeExt => Platform.isWindows ? '.exe' : '';

  Future<String> _resolveBinary(String name, String envVar) async {
    final override = Platform.environment[envVar];
    if (override != null && override.isNotEmpty && File(override).existsSync()) {
      return override;
    }
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(exeDir, 'native', _osDir, '$name$_exeExt'),
      p.join(exeDir, '$name$_exeExt'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    // Fall back to bare name; Process.start(runInShell) resolves it via PATH.
    return '$name$_exeExt';
  }

  @override
  Future<String?> getModelBasePath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final models = Directory(p.join(dir.path, 'models'));
      if (!models.existsSync()) models.createSync(recursive: true);
      return models.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<String?> getTailscaleIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          // Tailscale assigns addresses in the 100.64.0.0/10 CGNAT range.
          if (addr.address.startsWith('100.')) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getDeviceMetrics() async {
    // Cross-platform desktop metrics require per-OS native calls; the provider
    // keeps its initialized defaults when this returns null.
    return null;
  }

  @override
  Future<NativeServerResponse> startServer({
    required String modelPath,
    required int port,
    String? apiKey,
    int idleMinutes = 0,
    int batteryStopPercent = 0,
    bool thermalStop = true,
  }) async {
    if (_serverProc != null) {
      return NativeServerResponse(ok: true, status: 'running', port: _serverPort);
    }
    _serverError = null;
    _serverPort = port;

    if (!File(modelPath).existsSync()) {
      _serverError = 'model file not found: $modelPath';
      return NativeServerResponse(ok: false, status: 'stopped', message: _serverError);
    }

    try {
      final bin = await _resolveBinary('llama-server', 'BUILDIFY_LLAMA_SERVER');
      final args = <String>[
        '--model', modelPath,
        '--host', '127.0.0.1',
        '--port', '$port',
        if (apiKey != null && apiKey.isNotEmpty) ...['--api-key', apiKey],
      ];
      _serverProc = await Process.start(bin, args, runInShell: true);
      _serverProc!.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((_) {});
      _serverProc!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((line) {
        if (line.toLowerCase().contains('error')) _serverError = line.trim();
      });
      _serverProc!.exitCode.then((_) => _serverProc = null);
      return NativeServerResponse(ok: true, status: 'starting', port: port);
    } catch (e) {
      _serverError = 'failed to launch llama-server: $e';
      _serverProc = null;
      return NativeServerResponse(ok: false, status: 'stopped', message: _serverError);
    }
  }

  @override
  Future<NativeServerResponse> stopServer() async {
    final proc = _serverProc;
    _serverProc = null;
    if (proc == null) {
      return const NativeServerResponse(ok: true, status: 'stopped');
    }
    proc.kill(ProcessSignal.sigterm);
    await Future.any([proc.exitCode, Future.delayed(const Duration(seconds: 3))]);
    try {
      proc.kill(ProcessSignal.sigkill);
    } catch (_) {}
    return const NativeServerResponse(ok: true, status: 'stopped');
  }

  @override
  Future<NativeServerStatus?> getServerStatus() async {
    final running = _serverProc != null;
    return NativeServerStatus(
      status: running ? 'running' : 'stopped',
      port: _serverPort,
      lastError: _serverError,
    );
  }

  @override
  Future<NativeTunnelResponse> startTunnel({required int port, String? tunnelUrl}) async {
    if (_tunnelProc != null) {
      return NativeTunnelResponse(ok: true, status: _tunnelStatus);
    }
    _tunnelUrl = null;
    _tunnelError = null;
    _tunnelStatus = 'starting';
    try {
      final bin = await _resolveBinary('cloudflared', 'BUILDIFY_CLOUDFLARED');
      _tunnelProc = await Process.start(
        bin,
        ['tunnel', '--url', 'http://127.0.0.1:$port'],
        runInShell: true,
      );
      // trycloudflare prints the assigned URL to stderr.
      void scan(String line) {
        final match = RegExp(r'https://[a-z0-9-]+\.trycloudflare\.com').firstMatch(line);
        if (match != null) {
          _tunnelUrl = match.group(0);
          _tunnelStatus = 'running';
        }
      }
      _tunnelProc!.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(scan);
      _tunnelProc!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(scan);
      _tunnelProc!.exitCode.then((_) {
        _tunnelProc = null;
        if (_tunnelStatus != 'stopped') _tunnelStatus = 'failed';
      });
      return NativeTunnelResponse(ok: true, status: 'starting');
    } catch (e) {
      _tunnelError = 'failed to launch cloudflared: $e';
      _tunnelStatus = 'failed';
      _tunnelProc = null;
      return NativeTunnelResponse(ok: false, status: 'failed', message: _tunnelError);
    }
  }

  @override
  Future<NativeTunnelResponse> stopTunnel() async {
    final proc = _tunnelProc;
    _tunnelProc = null;
    _tunnelStatus = 'stopped';
    _tunnelUrl = null;
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }
    return const NativeTunnelResponse(ok: true, status: 'stopped');
  }

  @override
  Future<NativeTunnelStatus?> getTunnelStatus() async {
    return NativeTunnelStatus(
      status: _tunnelStatus,
      publicUrl: _tunnelUrl,
      lastError: _tunnelError,
    );
  }
}
