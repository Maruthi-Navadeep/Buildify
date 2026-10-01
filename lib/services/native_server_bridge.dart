import 'package:flutter/services.dart';

/// Platform-agnostic contract for driving the on-device AI server + tunnel.
///
/// Implemented by [NativeServerBridge] (Android/iOS, via MethodChannel) and by
/// DesktopServerBridge (Windows/Linux/macOS, via dart:io Process). The provider
/// depends only on this interface so the backend swaps by platform.
abstract class ServerBridge {
  Future<NativeServerResponse> startServer({
    required String modelPath,
    required int port,
    String? apiKey,
    int idleMinutes,
    int batteryStopPercent,
    bool thermalStop,
  });
  Future<NativeServerResponse> stopServer();
  Future<NativeServerStatus?> getServerStatus();
  Future<String?> getModelBasePath();
  Future<String?> getLocalIp();
  Future<String?> getTailscaleIp();
  Future<Map<String, dynamic>?> getDeviceMetrics();
  Future<NativeTunnelResponse> startTunnel({required int port, String? tunnelUrl});
  Future<NativeTunnelResponse> stopTunnel();
  Future<NativeTunnelStatus?> getTunnelStatus();
}

class NativeServerBridge implements ServerBridge {
  const NativeServerBridge();

  static const MethodChannel _channel = MethodChannel('buildify.ai/server');

  @override
  Future<NativeServerResponse> startServer({
    required String modelPath,
    required int port,
    String? apiKey,
    int idleMinutes = 0,
    int batteryStopPercent = 0,
    bool thermalStop = true,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'startServer',
        <String, dynamic>{
          'modelPath': modelPath,
          'port': port,
          if (apiKey != null && apiKey.isNotEmpty) 'apiKey': apiKey,
          'idleMinutes': idleMinutes,
          'batteryStopPct': batteryStopPercent,
          'thermalStop': thermalStop,
        },
      );
      return NativeServerResponse.fromMap(raw);
    } on PlatformException catch (e) {
      return NativeServerResponse(
        ok: false,
        status: 'stopped',
        message: e.message ?? e.code,
      );
    }
  }

  @override
  Future<NativeServerResponse> stopServer() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('stopServer');
      return NativeServerResponse.fromMap(raw);
    } on PlatformException catch (e) {
      return NativeServerResponse(
        ok: false,
        status: 'running',
        message: e.message ?? e.code,
      );
    }
  }

  @override
  Future<NativeServerStatus?> getServerStatus() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getServerStatus',
      );
      if (raw == null) return null;
      return NativeServerStatus.fromMap(raw);
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> getModelBasePath() async {
    try {
      return await _channel.invokeMethod<String>('getModelBasePath');
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> getLocalIp() async {
    try {
      return await _channel.invokeMethod<String>('getLocalIp');
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> getTailscaleIp() async {
    try {
      return await _channel.invokeMethod<String>('getTailscaleIp');
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getDeviceMetrics() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('getDeviceMetrics');
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<NativeTunnelResponse> startTunnel({
    required int port,
    String? tunnelUrl,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'startTunnel',
        <String, dynamic>{
          'port': port,
          if (tunnelUrl != null) 'tunnelUrl': tunnelUrl,
        },
      );
      return NativeTunnelResponse.fromMap(raw);
    } on PlatformException catch (e) {
      return NativeTunnelResponse(
        ok: false,
        status: 'stopped',
        message: e.message ?? e.code,
      );
    }
  }

  @override
  Future<NativeTunnelResponse> stopTunnel() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('stopTunnel');
      return NativeTunnelResponse.fromMap(raw);
    } on PlatformException catch (e) {
      return NativeTunnelResponse(
        ok: false,
        status: 'running',
        message: e.message ?? e.code,
      );
    }
  }

  @override
  Future<NativeTunnelStatus?> getTunnelStatus() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getTunnelStatus',
      );
      if (raw == null) return null;
      return NativeTunnelStatus.fromMap(raw);
    } on PlatformException {
      return null;
    }
  }
}

class NativeServerResponse {
  const NativeServerResponse({
    required this.ok,
    required this.status,
    this.port,
    this.message,
  });

  final bool ok;
  final String status;
  final int? port;
  final String? message;

  factory NativeServerResponse.fromMap(Map<String, dynamic>? data) {
    return NativeServerResponse(
      ok: data?['ok'] as bool? ?? false,
      status: data?['status'] as String? ?? 'stopped',
      port: data?['port'] as int?,
      message: data?['message'] as String?,
    );
  }
}

class NativeServerStatus {
  const NativeServerStatus({
    required this.status,
    required this.port,
    this.modelPath,
    this.lastError,
    this.stopReason,
  });

  final String status;
  final int port;
  final String? modelPath;
  final String? lastError;
  final String? stopReason;

  factory NativeServerStatus.fromMap(Map<String, dynamic> data) {
    return NativeServerStatus(
      status: data['status'] as String? ?? 'stopped',
      port: data['port'] as int? ?? 8080,
      modelPath: data['modelPath'] as String?,
      lastError: data['lastError'] as String?,
      stopReason: data['stopReason'] as String?,
    );
  }
}

class NativeTunnelResponse {
  const NativeTunnelResponse({
    required this.ok,
    required this.status,
    this.message,
  });

  final bool ok;
  final String status;
  final String? message;

  factory NativeTunnelResponse.fromMap(Map<String, dynamic>? data) {
    return NativeTunnelResponse(
      ok: data?['ok'] as bool? ?? false,
      status: data?['status'] as String? ?? 'stopped',
      message: data?['message'] as String?,
    );
  }
}

class NativeTunnelStatus {
  const NativeTunnelStatus({
    required this.status,
    this.publicUrl,
    this.lastError,
  });

  final String status;
  final String? publicUrl;
  final String? lastError;

  factory NativeTunnelStatus.fromMap(Map<String, dynamic> data) {
    return NativeTunnelStatus(
      status: data['status'] as String? ?? 'stopped',
      publicUrl: data['publicUrl'] as String?,
      lastError: data['lastError'] as String?,
    );
  }
}
