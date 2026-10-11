import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// SignalWeaver Cloud Relay — the REAL long-range transport for BlueChat.
///
/// Uses a free public MQTT broker (broker.emqx.io) reached over TLS
/// WebSockets, so there is no server to host and no account to create.
/// Distance is unlimited: any two devices with any form of internet
/// (mobile data or Wi-Fi) can message each other, even 100+ km apart.
///
/// Privacy: every chat payload is already end-to-end encrypted with the
/// pairwise AES-256 key from the Diffie-Hellman handshake BEFORE it is
/// published, so the public broker only ever carries ciphertext. Never
/// publish unencrypted 1:1 chat content through this transport.
///
/// Reliability: QoS 1 delivery to the broker, an offline outbox with
/// periodic retry, and end-to-end delivery ACKs handled by ChatProvider.
class WanLinkService {
  WanLinkService._privateConstructor();
  static final WanLinkService instance = WanLinkService._privateConstructor();

  // Free public MQTT brokers (no signup, no cost), tried in order until one
  // is reachable from the user's network. TLS is required on Android; the
  // WSS scheme handles the certificate handshake natively.
  static const List<List<dynamic>> _brokers = [
    ['wss://broker.emqx.io/mqtt', 8084],
    ['wss://broker.hivemq.com/mqtt', 8884],
    ['wss://test.mosquitto.org/', 8081],
  ];
  int _brokerIndex = 0;
  static const String _topicPrefix = 'bluechat/v1';

  MqttServerClient? _client;
  String _myAddress = '';
  bool _enabled = true;
  bool _connecting = false;
  String _status = 'offline'; // offline | connecting | online
  Timer? _reconnectTimer;
  Timer? _retryTimer;
  StreamSubscription? _updatesSub;

  // Offline outbox: packets that could not be delivered yet.
  final List<Map<String, dynamic>> _pendingOutgoing = [];
  static const int _maxPending = 50;
  static const int _maxAttempts = 60; // ~15 min of retries at 15s cadence

  final _packetController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get packetStream => _packetController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;
  String get status => _status;
  bool get isEnabled => _enabled;
  int get pendingCount => _pendingOutgoing.length;

  /// Starts the relay link for this device. [myAddress] must be the stable
  /// device identity used across BlueChat (the Bluetooth MAC address, or a
  /// fallback swmp_ id when the MAC is unavailable).
  void init(String myAddress) {
    if (myAddress.isEmpty || _myAddress.isNotEmpty) return;
    _myAddress = myAddress.toUpperCase();
    _connect();
  }

  /// Enables or disables WAN messaging entirely (user control).
  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      _reconnectTimer?.cancel();
      _retryTimer?.cancel();
      try {
        _client?.disconnect();
      } catch (_) {}
      _client = null;
      _setStatus('offline');
    } else {
      _connect();
    }
  }

  void _setStatus(String s) {
    if (_status == s) return;
    _status = s;
    _statusController.add(s);
  }

  Future<void> _connect() async {
    if (_connecting || !_enabled || _myAddress.isEmpty) return;
    _connecting = true;
    _setStatus('connecting');

    final broker = _brokers[_brokerIndex % _brokers.length];
    final brokerUri = broker[0] as String;
    final brokerPort = broker[1] as int;
    final clientId =
        'bc_${_myAddress.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final client = MqttServerClient.withPort(brokerUri, clientId, brokerPort);
    client.useWebSocket = true;
    // Some brokers (e.g. Mosquitto/libwebsockets) reject the default
    // multi-protocol subprotocol list; the single 'mqtt' identifier is
    // universally accepted.
    client.websocketProtocols = ['mqtt'];
    client.keepAlivePeriod = 30;
    client.logging(on: false);
    client.onConnected = () {
      _setStatus('online');
      _flushPending();
    };
    client.onDisconnected = () {
      _setStatus('offline');
      _scheduleReconnect();
    };

    try {
      final status = await client.connect();
      if (status?.state != MqttConnectionState.connected) {
        throw Exception('Broker refused connection: ${status?.state}');
      }
      _client = client;
      client.subscribe('$_topicPrefix/$_myAddress/inbox', MqttQos.atLeastOnce);
      _updatesSub = client.updates?.listen(_onUpdates);
      _setStatus('online');
      _startRetryLoop();
      print('WanLink: connected to relay $brokerUri as $_myAddress');
    } catch (e) {
      print('WanLink: relay $brokerUri connect failed: $e');
      try {
        client.disconnect();
      } catch (_) {}
      _client = null;
      _setStatus('offline');
      // Rotate to the next free broker and try again.
      _brokerIndex++;
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    if (!_enabled || _myAddress.isEmpty) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 20), _connect);
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage?>> c) {
    try {
      final rec = c.first.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(rec.payload.message);
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        decoded['wanTransport'] = true;
        _packetController.add(decoded);
      }
    } catch (e) {
      print('WanLink: dropped malformed relay packet: $e');
    }
  }

  /// Publishes a packet to the recipient's relay inbox.
  /// Returns true when the broker accepted the packet; otherwise the packet
  /// is queued in the outbox for retry and false is returned.
  bool sendToPeer(String recipientId, Map<String, dynamic> packet) {
    if (!_enabled || recipientId.isEmpty) return false;
    final target = recipientId.trim().toUpperCase();
    final payload = Map<String, dynamic>.from(packet)..['recipientId'] = target;

    if (_status == 'online' && _client != null) {
      try {
        final builder = MqttClientPayloadBuilder()..addString(jsonEncode(payload));
        _client!.publishMessage('$_topicPrefix/$target/inbox', MqttQos.atLeastOnce, builder.payload!);
        return true;
      } catch (e) {
        print('WanLink: publish failed, queuing for retry: $e');
      }
    }
    _enqueue(target, payload);
    return false;
  }

  void _enqueue(String target, Map<String, dynamic> payload) {
    if (_pendingOutgoing.length >= _maxPending) _pendingOutgoing.removeAt(0);
    _pendingOutgoing.add({'recipientId': target, 'packet': payload, 'attempts': 0});
  }

  void _startRetryLoop() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (_) => _flushPending());
  }

  void _flushPending() {
    if (_status != 'online' || _client == null || _pendingOutgoing.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    for (final item in _pendingOutgoing) {
      item['attempts'] = (item['attempts'] as int) + 1;
      if (item['attempts'] > _maxAttempts) {
        continue; // Give up; sender keeps the 'sent/failed' DB state.
      }
      try {
        final builder = MqttClientPayloadBuilder()..addString(jsonEncode(item['packet']));
        _client!.publishMessage(
          '$_topicPrefix/${item['recipientId']}/inbox',
          MqttQos.atLeastOnce,
          builder.payload!,
        );
      } catch (_) {
        remaining.add(item); // Broker write failed; retry next round.
      }
    }
    _pendingOutgoing
      ..clear()
      ..addAll(remaining);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _retryTimer?.cancel();
    _updatesSub?.cancel();
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
    _packetController.close();
    _statusController.close();
  }
}
