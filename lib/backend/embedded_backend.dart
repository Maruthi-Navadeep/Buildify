import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../services/database_helper.dart';
import '../services/static_site_server.dart';
import '../services/process_server.dart';
import '../services/native_server_bridge.dart';

enum BackendLogType { request, error, system }
enum HostingMode { persistent, ephemeral }

class BackendLogEvent {
  const BackendLogEvent({
    required this.id,
    required this.projectId,
    required this.sessionId,
    required this.message,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String sessionId;
  final String message;
  final BackendLogType type;
  final DateTime createdAt;
}

class BackendProject {
  const BackendProject({
    required this.id,
    required this.name,
    required this.repoProvider,
    required this.url,
    required this.lastDeployedAt,
    required this.isLive,
    this.hostingMode = HostingMode.persistent,
    this.localPath = '',
    this.branch = 'main',
    this.buildCommand = '',
    this.publishDir = '',
    this.baseDir = '',
    this.port = 3000,
    this.envVars = const {},
  });

  final String id;
  final String name;
  final String repoProvider;
  final String url;
  final DateTime? lastDeployedAt;
  final bool isLive;
  final HostingMode hostingMode;
  final String localPath;
  final String branch;
  final String buildCommand;
  final String publishDir;
  final String baseDir;
  final int port;
  final Map<String, String> envVars;

  BackendProject copyWith({
    String? name,
    String? repoProvider,
    String? url,
    DateTime? lastDeployedAt,
    bool? isLive,
    HostingMode? hostingMode,
    String? localPath,
    String? branch,
    String? buildCommand,
    String? publishDir,
    String? baseDir,
    int? port,
    Map<String, String>? envVars,
  }) {
    return BackendProject(
      id: id,
      name: name ?? this.name,
      repoProvider: repoProvider ?? this.repoProvider,
      url: url ?? this.url,
      lastDeployedAt: lastDeployedAt ?? this.lastDeployedAt,
      isLive: isLive ?? this.isLive,
      hostingMode: hostingMode ?? this.hostingMode,
      localPath: localPath ?? this.localPath,
      branch: branch ?? this.branch,
      buildCommand: buildCommand ?? this.buildCommand,
      publishDir: publishDir ?? this.publishDir,
      baseDir: baseDir ?? this.baseDir,
      port: port ?? this.port,
      envVars: envVars ?? this.envVars,
    );
  }
}

class BackendDeployment {
  const BackendDeployment({
    required this.id,
    required this.projectId,
    required this.framework,
    required this.sourceType,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String framework;
  final String sourceType;
  final DateTime createdAt;
}

class BackendSession {
  const BackendSession({
    required this.id,
    required this.projectId,
    required this.startedAt,
    required this.isRunning,
    required this.publicUrl,
    required this.tunnelProvider,
    required this.requestCount,
    required this.rps,
    required this.lowBattery,
  });

  final String id;
  final String projectId;
  final DateTime startedAt;
  final bool isRunning;
  final String publicUrl;
  final String tunnelProvider;
  final int requestCount;
  final double rps;
  final bool lowBattery;

  BackendSession copyWith({
    bool? isRunning,
    String? publicUrl,
    String? tunnelProvider,
    int? requestCount,
    double? rps,
    bool? lowBattery,
  }) {
    return BackendSession(
      id: id,
      projectId: projectId,
      startedAt: startedAt,
      isRunning: isRunning ?? this.isRunning,
      publicUrl: publicUrl ?? this.publicUrl,
      tunnelProvider: tunnelProvider ?? this.tunnelProvider,
      requestCount: requestCount ?? this.requestCount,
      rps: rps ?? this.rps,
      lowBattery: lowBattery ?? this.lowBattery,
    );
  }
}

class BackendState {
  const BackendState({
    required this.userName,
    required this.projects,
    required this.deployments,
    required this.activeSession,
    required this.logs,
    required this.hostMappings,
  });

  final String userName;
  final List<BackendProject> projects;
  final List<BackendDeployment> deployments;
  final BackendSession? activeSession;
  final List<BackendLogEvent> logs;
  final Map<String, String> hostMappings;

  BackendState copyWith({
    String? userName,
    List<BackendProject>? projects,
    List<BackendDeployment>? deployments,
    BackendSession? activeSession,
    List<BackendLogEvent>? logs,
    Map<String, String>? hostMappings,
  }) {
    return BackendState(
      userName: userName ?? this.userName,
      projects: projects ?? this.projects,
      deployments: deployments ?? this.deployments,
      activeSession: activeSession,
      logs: logs ?? this.logs,
      hostMappings: hostMappings ?? this.hostMappings,
    );
  }
}

class EmbeddedBackendService {
  EmbeddedBackendService()
    : _state = const BackendState(
        userName: 'user',
        projects: [],
        deployments: [],
        activeSession: null,
        logs: [],
        hostMappings: {},
      ) {
    unawaited(hydrateProjects());
  }

  final _uuid = const Uuid();
  final _rand = Random();
  final _stateController = StreamController<BackendState>.broadcast();
  final _projectLogControllers = <String, StreamController<BackendLogEvent>>{};
  final _sessionControllers = <String, StreamController<BackendSession>>{};
  final _staticServers = <String, StaticSiteServer>{};
  final _processServers = <String, ProcessServer>{};
  final _nativeBridge = const NativeServerBridge();
  Timer? _ticker;
  BackendState _state;

  BackendState get state => _state;
  Stream<BackendState> get stream => _stateController.stream;

  Future<void> hydrateProjects() async {
    try {
      final dbProjects = await DatabaseHelper.instance.getProjects();
      final loaded = dbProjects.map((row) {
        Map<String, String> parsedEnv = {};
        try {
          if (row['env_vars'] != null) {
            parsedEnv = Map<String, String>.from(jsonDecode(row['env_vars'] as String));
          }
        } catch (_) {}
        return BackendProject(
          id: row['id'] as String,
          name: row['name'] as String,
          repoProvider: row['type'] as String,
          url: row['source_uri'] as String,
          lastDeployedAt: DateTime.fromMillisecondsSinceEpoch(row['last_active_at'] as int),
          isLive: row['desired_state'] == 'running',
          hostingMode: row['hosting_mode'] == 'ephemeral'
              ? HostingMode.ephemeral
              : HostingMode.persistent,
          localPath: row['local_path'] as String,
          branch: row['branch'] as String? ?? 'main',
          buildCommand: row['build_command'] as String? ?? '',
          publishDir: row['publish_dir'] as String? ?? '',
          baseDir: row['base_dir'] as String? ?? '',
          port: row['port'] as int? ?? 3000,
          envVars: parsedEnv,
        );
      }).toList();
      _emit(_state.copyWith(projects: loaded));

      // Resume the project that was live when the app was last closed. Only one
      // tunnel/session is supported at a time, so restore the most recently
      // active persistent project whose desired_state is 'running'.
      await _restoreRunningProject(dbProjects);
    } catch (_) {}
  }

  /// Persists a project's run intent so it can be resumed after an app restart.
  Future<void> _persistDesiredState(String projectId, String state) async {
    try {
      await DatabaseHelper.instance.updateProject(projectId, {
        'desired_state': state,
        'last_active_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  /// Auto-restarts the persistent project that was running before the last
  /// shutdown. Any stale extra 'running' rows are reset to 'stopped' since the
  /// backend only supports a single active session/tunnel.
  Future<void> _restoreRunningProject(List<Map<String, dynamic>> rows) async {
    final running = rows
        .where((r) =>
            r['desired_state'] == 'running' &&
            (r['hosting_mode'] ?? 'persistent') != 'ephemeral')
        .toList();
    if (running.isEmpty) return;

    running.sort((a, b) =>
        (b['last_active_at'] as int).compareTo(a['last_active_at'] as int));

    // Reset any stale extra running rows — only one can actually be live.
    for (final r in running.skip(1)) {
      final id = r['id'] as String;
      await _persistDesiredState(id, 'stopped');
      _updateProject(id, (p) => p.copyWith(isLive: false));
    }

    final targetId = running.first['id'] as String;
    try {
      _log(targetId, 'system', '-- resuming project after app restart --',
          BackendLogType.system);
      await startSession(projectId: targetId);
    } catch (e) {
      _log(targetId, 'system', '[ERR] Auto-resume failed: $e',
          BackendLogType.error);
      await _persistDesiredState(targetId, 'stopped');
      _updateProject(targetId, (p) => p.copyWith(isLive: false));
    }
  }

  Future<void> devLogin({String userName = 'user'}) async {
    _emit(_state.copyWith(userName: userName));
  }

  Future<List<BackendProject>> listProjects() async => _state.projects;

  Future<BackendProject> createProject({
    required String name,
    required String sourceType,
    String? customUrl,
    HostingMode hostingMode = HostingMode.persistent,
    String? customLocalPath,
    String branch = 'main',
    String buildCommand = '',
    String publishDir = '',
    String baseDir = '',
    Map<String, String> envVars = const {},
  }) async {
    final slug = name.toLowerCase().replaceAll(' ', '-');
    final id = _uuid.v4();

    String localPath = customLocalPath ?? '';
    if (localPath.isEmpty) {
      if (hostingMode == HostingMode.persistent) {
        final docDir = await getApplicationDocumentsDirectory();
        localPath = join(docDir.path, 'projects', id);
      } else {
        final tempDir = await getTemporaryDirectory();
        localPath = join(tempDir.path, 'ephemeral', id);
      }
    }
    try {
      final dir = Directory(localPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (_) {}

    int assignedPort = 3000;
    final usedPorts = _state.projects.map((p) => p.port).toSet();
    while (usedPorts.contains(assignedPort) && assignedPort < 3100) {
      assignedPort++;
    }
    if (assignedPort >= 3100) throw Exception('Port exhaustion: maximum of 100 projects allowed.');

    final p = BackendProject(
      id: id,
      name: name,
      repoProvider: sourceType,
      url: customUrl ?? 'https://$slug.buildify.app',
      lastDeployedAt: DateTime.now(),
      isLive: false,
      hostingMode: hostingMode,
      localPath: localPath,
      branch: branch,
      buildCommand: buildCommand,
      publishDir: publishDir,
      baseDir: baseDir,
      port: assignedPort,
      envVars: envVars,
    );

    if (hostingMode == HostingMode.persistent) {
      try {
        await DatabaseHelper.instance.insertProject({
          'id': p.id,
          'name': p.name,
          'type': p.repoProvider,
          'hosting_mode': 'persistent',
          'source_uri': p.url,
          'local_path': p.localPath,
          'port': p.port,
          'subdomain': slug,
          'env_vars': jsonEncode(p.envVars),
          'branch': p.branch,
          'build_command': p.buildCommand,
          'publish_dir': p.publishDir,
          'base_dir': p.baseDir,
          'desired_state': 'stopped',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'last_active_at': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}
    }

    final host = Uri.tryParse(p.url)?.host;
    final hostMappings = Map<String, String>.from(_state.hostMappings);
    if (host != null && host.isNotEmpty) {
      hostMappings[host] = p.id;
    }
    _emit(
      _state.copyWith(
        projects: [..._state.projects, p],
        hostMappings: hostMappings,
      ),
    );
    return p;
  }

  String generateRandomSubdomain() {
    const adjectives = [
      'amazing',
      'golden',
      'swift',
      'brave',
      'silent',
      'lucky',
      'frozen',
      'bright',
      'rapid',
      'solar',
    ];
    const nouns = [
      'sunflower',
      'bridge',
      'harbor',
      'engine',
      'orbit',
      'river',
      'forest',
      'rocket',
      'signal',
      'anchor',
    ];
    final name =
        '${adjectives[_rand.nextInt(adjectives.length)]}-${nouns[_rand.nextInt(nouns.length)]}-${10 + _rand.nextInt(90)}';
    return name;
  }

  BackendProject? resolveHostname(String hostname) {
    final projectId = _state.hostMappings[hostname];
    if (projectId == null) return null;
    for (final project in _state.projects) {
      if (project.id == projectId) return project;
    }
    return null;
  }

  Future<BackendDeployment> createDeployment({
    required String projectId,
    required String framework,
    required String sourceType,
  }) async {
    final d = BackendDeployment(
      id: _uuid.v4(),
      projectId: projectId,
      framework: framework,
      sourceType: sourceType,
      createdAt: DateTime.now(),
    );
    _emit(_state.copyWith(deployments: [..._state.deployments, d]));
    _updateProject(projectId, (p) => p.copyWith(lastDeployedAt: d.createdAt));
    _log(
      projectId,
      _state.activeSession?.id ?? 'none',
      '-- deployment created --',
      BackendLogType.system,
    );
    return d;
  }

  Future<BackendSession> startSession({
    required String projectId,
    String? publicUrl,
    String tunnelProvider = 'cloudflare',
  }) async {
    _ticker?.cancel();

    final project = _state.projects.firstWhere((p) => p.id == projectId);

    // Resolve working directory (base_dir is relative to localPath)
    final workDir = project.baseDir.isNotEmpty
        ? join(project.localPath, project.baseDir)
        : project.localPath;

    // --- Build step (static sites only) ---
    // For process-type projects, buildCommand is the server start command,
    // not a build step — skip the blocking build phase for them.
    final isProcessServer = _needsProcessServer(project.repoProvider);

    if (!isProcessServer && project.buildCommand.isNotEmpty) {
      _log(projectId, 'system', '-- running build: ${project.buildCommand} --',
          BackendLogType.system);

      final buildOk = await ProcessServer.runBuild(
        command: project.buildCommand,
        workingDirectory: workDir,
        environment: project.envVars,
        onLog: (msg, {bool isError = false}) {
          _log(projectId, 'build', msg,
              isError ? BackendLogType.error : BackendLogType.system);
        },
      );

      if (!buildOk) {
        _log(projectId, 'system', '-- build failed; aborting start --',
            BackendLogType.error);
        throw Exception('Build command failed. Check logs for details.');
      }
    }

    // --- Server start ---
    if (isProcessServer) {
      if (project.buildCommand.isEmpty) {
        _log(projectId, 'system',
            '[ERR] No start command configured for process server',
            BackendLogType.error);
        throw Exception(
            'No start command configured. Set a start command in project settings.');
      }

      _log(projectId, 'system',
          '-- starting process server on port ${project.port} --',
          BackendLogType.system);

      final srv = ProcessServer(
        command: project.buildCommand,
        workingDirectory: workDir,
        port: project.port,
        environment: project.envVars,
        onLog: (msg, {bool isError = false}) {
          _log(projectId, 'server', msg,
              isError ? BackendLogType.error : BackendLogType.request);
        },
      );
      try {
        await srv.start();
        _processServers[projectId] = srv;
      } catch (e) {
        _log(projectId, 'system', '[ERR] Failed to start process: $e',
            BackendLogType.error);
        rethrow;
      }
    } else {
      // Static file server
      _log(projectId, 'system',
          '-- starting static site server on port ${project.port} --',
          BackendLogType.system);

      final server = StaticSiteServer(
        localPath: project.localPath,
        port: project.port,
        publishDir: project.publishDir,
        onLog: (msg, {bool isError = false}) {
          _log(projectId, 'server', msg,
              isError ? BackendLogType.error : BackendLogType.request);
        },
      );
      try {
        await server.start();
        _staticServers[projectId] = server;
      } catch (e) {
        _log(projectId, 'system',
            '[ERR] Failed to bind server port ${project.port}: $e',
            BackendLogType.error);
        rethrow;
      }
    }

    _log(projectId, 'system', '-- starting cloudflare tunnel --',
        BackendLogType.system);

    await _nativeBridge.startTunnel(port: project.port);

    final session = BackendSession(
      id: _uuid.v4(),
      projectId: projectId,
      startedAt: DateTime.now(),
      isRunning: true,
      publicUrl: publicUrl ?? project.url,
      tunnelProvider: tunnelProvider,
      requestCount: 0,
      rps: 0,
      lowBattery: false,
    );
    _updateProject(projectId, (p) => p.copyWith(isLive: true));
    _emit(_state.copyWith(activeSession: session));

    // Persist run intent so this project resumes automatically after a restart.
    if (project.hostingMode == HostingMode.persistent) {
      await _persistDesiredState(projectId, 'running');
    }

    // Poll for the tunnel public URL
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) async {
      final current = _state.activeSession;
      if (current == null || !current.isRunning) return;

      final status = await _nativeBridge.getTunnelStatus();
      if (status != null &&
          status.publicUrl != null &&
          status.publicUrl!.isNotEmpty) {
        if (current.publicUrl != status.publicUrl) {
          final next = current.copyWith(publicUrl: status.publicUrl);
          _emit(_state.copyWith(activeSession: next));
          _log(projectId, current.id,
              '-- tunnel active at ${status.publicUrl} --',
              BackendLogType.system);
        }
      }
    });

    return session;
  }

  bool _needsProcessServer(String repoProvider) {
    final t = repoProvider.toLowerCase();
    return t == 'nodejs' ||
        t == 'node.js' ||
        t == 'node' ||
        t == 'python' ||
        t == 'python fastapi' ||
        t == 'flask' ||
        t == 'fastapi';
  }

  Future<void> stopSession({required String sessionId}) async {
    final current = _state.activeSession;
    if (current == null || current.id != sessionId) return;
    _ticker?.cancel();
    
    _log(
      current.projectId,
      sessionId,
      '-- stopping server and tunnel --',
      BackendLogType.system,
    );
    
    // Stop static server or process server
    await _staticServers[current.projectId]?.stop();
    _staticServers.remove(current.projectId);
    await _processServers[current.projectId]?.stop();
    _processServers.remove(current.projectId);
    
    // Stop tunnel
    await _nativeBridge.stopTunnel();

    _updateProject(current.projectId, (p) => p.copyWith(isLive: false));
    _emit(_state.copyWith(activeSession: null));

    final proj = _state.projects.where((p) => p.id == current.projectId).firstOrNull;
    if (proj != null && proj.hostingMode == HostingMode.persistent) {
      // Clear run intent so it stays stopped across restarts.
      await _persistDesiredState(current.projectId, 'stopped');
    }
    if (proj != null && proj.hostingMode == HostingMode.ephemeral) {
      await deleteProject(proj.id);
    }
  }

  Future<void> deleteProject(String id) async {
    final proj = _state.projects.where((p) => p.id == id).firstOrNull;
    if (proj == null) return;

    if (proj.hostingMode == HostingMode.persistent) {
      try {
        await DatabaseHelper.instance.deleteProject(id);
      } catch (_) {}
    } else {
      try {
        final dir = Directory(proj.localPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    }

    final next = _state.projects.where((p) => p.id != id).toList();
    _emit(_state.copyWith(projects: next));
  }

  Stream<BackendLogEvent> logsStream(String projectId) {
    return _projectLogControllers
        .putIfAbsent(
          projectId,
          () => StreamController<BackendLogEvent>.broadcast(),
        )
        .stream;
  }

  Stream<BackendSession> sessionStatusStream(String sessionId) {
    return _sessionControllers
        .putIfAbsent(
          sessionId,
          () => StreamController<BackendSession>.broadcast(),
        )
        .stream;
  }

  void dispose() {
    _ticker?.cancel();
    _stateController.close();
    for (final c in _projectLogControllers.values) {
      c.close();
    }
    for (final c in _sessionControllers.values) {
      c.close();
    }
  }

  void _emit(BackendState next) {
    _state = next;
    _stateController.add(_state);
    final session = _state.activeSession;
    if (session != null && _sessionControllers.containsKey(session.id)) {
      _sessionControllers[session.id]!.add(session);
    }
  }

  void _log(
    String projectId,
    String sessionId,
    String message,
    BackendLogType type,
  ) {
    final event = BackendLogEvent(
      id: _uuid.v4(),
      projectId: projectId,
      sessionId: sessionId,
      message: message,
      type: type,
      createdAt: DateTime.now(),
    );
    final logs = [..._state.logs, event];
    _emit(
      _state.copyWith(
        logs: logs.length > 300 ? logs.sublist(logs.length - 300) : logs,
      ),
    );
    if (_projectLogControllers.containsKey(projectId)) {
      _projectLogControllers[projectId]!.add(event);
    }
  }

  void _updateProject(
    String id,
    BackendProject Function(BackendProject) mapper,
  ) {
    final next =
        _state.projects.map((p) => p.id == id ? mapper(p) : p).toList();
    _emit(_state.copyWith(projects: next));
  }
}
