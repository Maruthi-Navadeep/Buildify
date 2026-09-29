import 'dart:convert';
import 'dart:io';

class ProcessServer {
  Process? _process;
  final String command;
  final String workingDirectory;
  final int port;
  final Map<String, String> environment;
  final void Function(String message, {bool isError})? onLog;

  ProcessServer({
    required this.command,
    required this.workingDirectory,
    required this.port,
    this.environment = const {},
    this.onLog,
  });

  bool get isRunning => _process != null;

  Future<void> start() async {
    if (_process != null) return;

    onLog?.call('[server] starting process: $command');

    final env = {...Platform.environment, 'PORT': '$port', ...environment};

    try {
      if (Platform.isWindows) {
        _process = await Process.start(
          'cmd',
          ['/c', command],
          workingDirectory: workingDirectory,
          environment: env,
          runInShell: false,
        );
      } else {
        _process = await Process.start(
          '/system/bin/sh',
          ['-c', command],
          workingDirectory: workingDirectory,
          environment: env,
        );
      }
    } catch (_) {
      // Fallback: let the OS resolve sh/cmd
      _process = await Process.start(
        Platform.isWindows ? 'cmd' : 'sh',
        [Platform.isWindows ? '/c' : '-c', command],
        workingDirectory: workingDirectory,
        environment: env,
        runInShell: true,
      );
    }

    _process!.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) => onLog?.call('[stdout] $line'));

    _process!.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) => onLog?.call('[stderr] $line', isError: true));

    _process!.exitCode.then((code) {
      onLog?.call('[server] process exited with code $code',
          isError: code != 0);
      _process = null;
    });
  }

  Future<void> stop() async {
    final proc = _process;
    if (proc == null) return;
    _process = null;

    proc.kill(ProcessSignal.sigterm);
    // Give it 3 seconds to exit gracefully before force-killing
    await Future.any([
      proc.exitCode,
      Future.delayed(const Duration(seconds: 3)),
    ]);
    try {
      proc.kill(ProcessSignal.sigkill);
    } catch (_) {}
  }

  /// Runs a build command to completion and streams its output.
  /// Returns true on exit code 0, false otherwise.
  static Future<bool> runBuild({
    required String command,
    required String workingDirectory,
    required Map<String, String> environment,
    required void Function(String, {bool isError}) onLog,
  }) async {
    onLog('[build] $ $command');

    Process process;
    try {
      if (Platform.isWindows) {
        process = await Process.start(
          'cmd',
          ['/c', command],
          workingDirectory: workingDirectory,
          environment: {...Platform.environment, ...environment},
          runInShell: false,
        );
      } else {
        process = await Process.start(
          '/system/bin/sh',
          ['-c', command],
          workingDirectory: workingDirectory,
          environment: {...Platform.environment, ...environment},
        );
      }
    } catch (_) {
      process = await Process.start(
        Platform.isWindows ? 'cmd' : 'sh',
        [Platform.isWindows ? '/c' : '-c', command],
        workingDirectory: workingDirectory,
        environment: {...Platform.environment, ...environment},
        runInShell: true,
      );
    }

    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) => onLog('[build] $line'));

    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) => onLog('[build] $line', isError: true));

    final exitCode = await process.exitCode;
    if (exitCode == 0) {
      onLog('[build] completed successfully (exit 0)');
      return true;
    } else {
      onLog('[build] failed — exit code $exitCode', isError: true);
      return false;
    }
  }
}
