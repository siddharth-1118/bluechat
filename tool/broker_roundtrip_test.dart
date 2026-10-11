// Live verification that BlueChat's cloud relay endpoint works:
// connect over WSS -> subscribe -> publish -> receive own message back.
import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

Future<void> main(List<String> args) async {
  // Optional args: <uri> <port> — defaults to the production relay broker.
  final brokerUri = args.isNotEmpty ? args[0] : 'wss://broker.emqx.io/mqtt';
  final brokerPort = args.length > 1 ? int.parse(args[1]) : 8084;
  print('Relay endpoint under test: $brokerUri port $brokerPort');

  final topic = 'bluechat/v1/_relaytest_${DateTime.now().millisecondsSinceEpoch}/inbox';
  final client = MqttServerClient.withPort(
    brokerUri,
    'bc_relaytest_${DateTime.now().millisecondsSinceEpoch % 1000000}',
    brokerPort,
  );
  client.useWebSocket = true;
  client.websocketProtocols = ['mqtt']; // Some brokers reject multi-protocol lists.
  client.keepAlivePeriod = 20;
  client.logging(on: false);

  final status = await client.connect();
  if (status?.state != MqttConnectionState.connected) {
    print('FAIL: not connected (${status?.state})');
    client.disconnect();
    throw StateError('relay connect failed');
  }
  print('PASS: connected to $brokerUri port $brokerPort');

  client.subscribe(topic, MqttQos.atLeastOnce);

  final received = Completer<String>();
  client.updates?.listen((c) {
    final rec = c.first.payload as MqttPublishMessage;
    final payload = MqttPublishPayload.bytesToStringAsString(rec.payload.message);
    if (!received.isCompleted) received.complete(payload);
  });

  // Give the SUBACK a moment, then publish an encrypted-looking payload.
  await Future.delayed(const Duration(seconds: 2));
  final testPacket = jsonEncode({
    'id': 'test_1',
    'type': 'encrypted_text',
    'recipientId': 'TEST',
    'body': jsonEncode({'iv': 'dGVzdA==', 'ct': 'Q1JJUFRPS0VOVF9PTkxZ'}), // ciphertext only
  });
  final builder = MqttClientPayloadBuilder()..addString(testPacket);
  client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  print('PASS: published QoS1 message to $topic');

  final echoed = await received.future.timeout(const Duration(seconds: 15));
  if (echoed != testPacket) {
    print('FAIL: payload mismatch: $echoed');
    throw StateError('payload mismatch');
  }
  print('PASS: received own message back through the broker (round trip ok)');

  client.disconnect();
  print('ALL PASS');
}
