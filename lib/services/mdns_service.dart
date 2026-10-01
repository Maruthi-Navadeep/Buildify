import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Buildify Discovery Beacon Service
///
/// Listens on UDP broadcast port 8257 for discovery requests from Buildify SDK
/// clients and responds with the device's server details and status.
///
/// **Security model:** The beacon requires a shared secret that callers must
/// include in the discovery message as `BUILDIFY_DISCOVER:<secret>`. The
/// secret is generated on each [start] call (or supplied by the caller) and
/// must be delivered out-of-band to trusted SDK peers (e.g. via QR code or
/// copy-paste). Any device on the same Wi-Fi that doesn't know the secret
/// receives no response, preventing casual enumeration of the AI endpoint and
/// leakage of the public tunnel URL to untrusted peers.
class BuildifyDiscoveryBeacon {
  static const int beaconPort = 8257;
  RawDatagramSocket? _socket;
  bool _isRunning = false;
  String? _secret;

  bool get isRunning => _isRunning;

  /// The shared secret that SDK peers must include in discovery probes.
  /// Populated after [start] is called; null while stopped.
  String? get secret => _secret;

  /// Starts listening for discovery broadcasts.
  ///
  /// [secret] — if provided, used as the shared secret; otherwise a random
  /// 8-character hex token is generated. Expose this to trusted clients only
  /// (e.g. QR code, Settings → Share).
  Future<void> start({
    required int serverPort,
    String? modelName,
    String? tunnelUrl,
    String? secret,
    InternetAddress? bindAddress,
  }) async {
    if (_isRunning) return;

    _secret = secret ?? _generateSecret();

    try {
      _socket = await RawDatagramSocket.bind(
        bindAddress ?? InternetAddress.anyIPv4,
        beaconPort,
        reuseAddress: true,
      );
      _socket?.broadcastEnabled = true;
      _isRunning = true;

      _socket?.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _socket?.receive();
        if (datagram == null) return;

        try {
          final message = utf8.decode(datagram.data).trim();
          // Require the format: BUILDIFY_DISCOVER:<secret>
          final expectedPrefix = 'BUILDIFY_DISCOVER:${_secret!}';
          if (!message.startsWith(expectedPrefix)) return;

          final payload = jsonEncode({
            'service': 'buildify-ai',
            'version': '1.0.0',
            'port': serverPort,
            'model': modelName ?? 'default',
            'tunnel_url': tunnelUrl,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });

          final replyBytes = utf8.encode(payload);
          _socket?.send(replyBytes, datagram.address, datagram.port);
        } catch (_) {}
      });
    } catch (_) {
      // Ignored if port is occupied or socket fails
      _isRunning = false;
      _secret = null;
    }
  }

  /// Stops the beacon service.
  void stop() {
    _isRunning = false;
    _secret = null;
    _socket?.close();
    _socket = null;
  }

  static String _generateSecret() {
    final rng = Random.secure();
    return List.generate(8, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
