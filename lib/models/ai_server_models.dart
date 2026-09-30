enum ServerStatus { stopped, starting, running, stopping }

enum TunnelStatus { stopped, starting, running, failed }

enum ModelDownloadStatus { notDownloaded, downloading, downloaded }

class ModelProfile {
  const ModelProfile({
    required this.id,
    required this.name,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeLabel,
    required this.speed,
    required this.quality,
    required this.requiredRamGb,
    required this.description,
  });

  final String id;
  final String name;
  final String fileName;
  final String downloadUrl;
  final String sizeLabel;
  final String speed;
  final String quality;
  final int requiredRamGb;
  final String description;

  factory ModelProfile.fromJson(Map<String, dynamic> json) {
    return ModelProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      fileName: json['fileName'] as String,
      downloadUrl: json['downloadUrl'] as String,
      sizeLabel: json['sizeLabel'] as String,
      speed: json['speed'] as String,
      quality: json['quality'] as String,
      requiredRamGb: json['requiredRamGb'] as int,
      description: json['description'] as String,
    );
  }
}

class ModelDownload {
  const ModelDownload({required this.status, required this.progress});

  final ModelDownloadStatus status;
  final double progress;

  ModelDownload copyWith({ModelDownloadStatus? status, double? progress}) {
    return ModelDownload(
      status: status ?? this.status,
      progress: progress ?? this.progress,
    );
  }
}

class DeviceSnapshot {
  const DeviceSnapshot({
    required this.ramGb,
    required this.availRamGb,
    required this.freeStorageGb,
    required this.batteryPercent,
    required this.batteryCharging,
    required this.ipAddress,
    required this.tailscaleIp,
    required this.cpuLabel,
  });

  final int ramGb;
  final double availRamGb;
  final double freeStorageGb;
  final int batteryPercent;
  final bool batteryCharging;
  final String ipAddress;
  final String? tailscaleIp;
  final String cpuLabel;

  DeviceSnapshot copyWith({
    int? ramGb,
    double? availRamGb,
    double? freeStorageGb,
    int? batteryPercent,
    bool? batteryCharging,
    String? ipAddress,
    String? tailscaleIp,
    String? cpuLabel,
  }) {
    return DeviceSnapshot(
      ramGb: ramGb ?? this.ramGb,
      availRamGb: availRamGb ?? this.availRamGb,
      freeStorageGb: freeStorageGb ?? this.freeStorageGb,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      batteryCharging: batteryCharging ?? this.batteryCharging,
      ipAddress: ipAddress ?? this.ipAddress,
      tailscaleIp: tailscaleIp ?? this.tailscaleIp,
      cpuLabel: cpuLabel ?? this.cpuLabel,
    );
  }
}

class TunnelState {
  const TunnelState({
    required this.status,
    this.publicUrl,
    this.lastError,
  });

  final TunnelStatus status;
  final String? publicUrl;
  final String? lastError;

  TunnelState copyWith({
    TunnelStatus? status,
    String? publicUrl,
    String? lastError,
  }) {
    return TunnelState(
      status: status ?? this.status,
      publicUrl: publicUrl ?? this.publicUrl,
      lastError: lastError ?? this.lastError,
    );
  }
}

class ServerLog {
  ServerLog(this.message, this.type) : createdAt = DateTime.now();

  final String message;
  final LogType type;
  final DateTime createdAt;
}

enum LogType { system, request, warning }

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.fromUser,
    required this.createdAt,
  });

  final String text;
  final bool fromUser;
  final DateTime createdAt;
}

class SecuritySettings {
  const SecuritySettings({
    required this.requireApiKey,
    required this.apiKey,
    required this.idleTimeoutMinutes,
    required this.batteryStopPercent,
    required this.thermalStop,
  });

  final bool requireApiKey;
  final String apiKey;
  final int idleTimeoutMinutes;
  final int batteryStopPercent;
  final bool thermalStop;

  static const empty = SecuritySettings(
    requireApiKey: false,
    apiKey: '',
    idleTimeoutMinutes: 0,
    batteryStopPercent: 0,
    thermalStop: true,
  );

  String get maskedApiKey {
    if (apiKey.isEmpty) return '—';
    if (apiKey.length <= 6) return '••••••';
    return '${apiKey.substring(0, 4)}…${apiKey.substring(apiKey.length - 4)}';
  }

  SecuritySettings copyWith({
    bool? requireApiKey,
    String? apiKey,
    int? idleTimeoutMinutes,
    int? batteryStopPercent,
    bool? thermalStop,
  }) {
    return SecuritySettings(
      requireApiKey: requireApiKey ?? this.requireApiKey,
      apiKey: apiKey ?? this.apiKey,
      idleTimeoutMinutes: idleTimeoutMinutes ?? this.idleTimeoutMinutes,
      batteryStopPercent: batteryStopPercent ?? this.batteryStopPercent,
      thermalStop: thermalStop ?? this.thermalStop,
    );
  }
}

class AiServerState {
  const AiServerState({
    required this.models,
    required this.downloads,
    required this.device,
    required this.selectedModelId,
    required this.status,
    required this.port,
    required this.requestCount,
    required this.requestsPerSecond,
    required this.uptime,
    required this.lowPowerMode,
    required this.temperature,
    required this.tokenLimit,
    required this.logs,
    required this.chat,
    required this.security,
    required this.tunnel,
  });

  final List<ModelProfile> models;
  final Map<String, ModelDownload> downloads;
  final DeviceSnapshot device;
  final String selectedModelId;
  final ServerStatus status;
  final int port;
  final int requestCount;
  final double requestsPerSecond;
  final Duration uptime;
  final bool lowPowerMode;
  final double temperature;
  final int tokenLimit;
  final List<ServerLog> logs;
  final List<ChatMessage> chat;
  final SecuritySettings security;
  final TunnelState tunnel;

  AiServerState copyWith({
    List<ModelProfile>? models,
    Map<String, ModelDownload>? downloads,
    DeviceSnapshot? device,
    String? selectedModelId,
    ServerStatus? status,
    int? port,
    int? requestCount,
    double? requestsPerSecond,
    Duration? uptime,
    bool? lowPowerMode,
    double? temperature,
    int? tokenLimit,
    List<ServerLog>? logs,
    List<ChatMessage>? chat,
    SecuritySettings? security,
    TunnelState? tunnel,
  }) {
    return AiServerState(
      models: models ?? this.models,
      downloads: downloads ?? this.downloads,
      device: device ?? this.device,
      selectedModelId: selectedModelId ?? this.selectedModelId,
      status: status ?? this.status,
      port: port ?? this.port,
      requestCount: requestCount ?? this.requestCount,
      requestsPerSecond: requestsPerSecond ?? this.requestsPerSecond,
      uptime: uptime ?? this.uptime,
      lowPowerMode: lowPowerMode ?? this.lowPowerMode,
      temperature: temperature ?? this.temperature,
      tokenLimit: tokenLimit ?? this.tokenLimit,
      logs: logs ?? this.logs,
      chat: chat ?? this.chat,
      security: security ?? this.security,
      tunnel: tunnel ?? this.tunnel,
    );
  }
}
