import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:buildify_flutter/services/mdns_service.dart';

void main() {
  test(
    'BuildifyDiscoveryBeacon responds to discovery query',
    () async {
      final beacon = BuildifyDiscoveryBeacon();
      await beacon.start(
        serverPort: 8080,
        modelName: 'gemma-2b',
        bindAddress: InternetAddress.loopbackIPv4,
      );
      expect(beacon.isRunning, isTrue);

      final client =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final completer = Completer<Map<String, dynamic>>();

      client.listen((event) {
        if (event == RawSocketEvent.read) {
          final packet = client.receive();
          if (packet != null) {
            final json = jsonDecode(utf8.decode(packet.data));
            if (!completer.isCompleted) completer.complete(json);
          }
        }
      });

      final query = utf8.encode('BUILDIFY_DISCOVER');
      client.send(
          query, InternetAddress.loopbackIPv4, BuildifyDiscoveryBeacon.beaconPort);

      final result =
          await completer.future.timeout(const Duration(seconds: 5));
      expect(result['service'], 'buildify-ai');
      expect(result['port'], 8080);
      expect(result['model'], 'gemma-2b');

      client.close();
      beacon.stop();
      expect(beacon.isRunning, isFalse);
    },
    // UDP loopback is unreliable in sandboxed CI; skip there.
    skip: Platform.environment.containsKey('CI'),
  );
}
