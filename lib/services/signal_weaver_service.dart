import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bluetooth_service.dart';
import '../database/database_helper.dart';

class SignalWeaverService {
  SignalWeaverService._privateConstructor();
  static final SignalWeaverService instance = SignalWeaverService._privateConstructor();

  // --- Identity ---
  String _myId = "";
  String _myIp = "";
  String _myName = "";
  String _myMacAddress = "";

  // --- Active Pools & States ---
  final Map<String, Socket> _wifiConnections = {}; // IP -> TCP Socket
  final Map<String, String> _macToIp = {};         // MAC -> IP
  final Map<String, String> _ipToMac = {};         // IP -> MAC
  final Map<String, String> _ipToName = {};        // IP -> Name
  final Set<String> _seenPacketIds = {};           // Track routed packet IDs to avoid loops
  
  // --- Routing History Log ---
  final List<Map<String, dynamic>> _routingLogs = [];
  final _logsController = StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get logsStream => _logsController.stream;
  List<Map<String, dynamic>> get currentLogs => List.unmodifiable(_routingLogs);

  // --- Incoming Message Channel for ChatProvider ---
  final _packetStreamController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get packetStream => _packetStreamController.stream;

  // --- Network State Streams ---
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;

  // --- Sockets ---
  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  Timer? _announceTimer;
  Timer? _pingTimer;

  bool _isInitialized = false;
  bool _isUdpScanning = false;
  bool _isTcpServerRunning = false;
  bool _isInternetAvailable = false;
  
  // --- Simulated Distance Configuration ---
  bool _isWanSimulated = false;
  double _simulatedDistance = 0.0; // in km

  // Getters
  String get myIp => _myIp;
  String get myMacAddress => _myMacAddress;
  List<String> get connectedIps => _wifiConnections.keys.toList();
  Map<String, String> get macToIp => Map.unmodifiable(_macToIp);
  Map<String, String> get ipToName => Map.unmodifiable(_ipToName);
  bool get isUdpScanning => _isUdpScanning;
  bool get isTcpServerRunning => _isTcpServerRunning;
  bool get isInternetAvailable => _isInternetAvailable;
  bool get isWanSimulated => _isWanSimulated;
  double get simulatedDistance => _simulatedDistance;

  // --- Initialization ---

  Future<void> init(String username) async {
    if (_isInitialized) return;
    _myName = username;
    
    // Create random local device ID if mac address isn't loaded yet
    final prefs = await SharedPreferences.getInstance();
    _myId = prefs.getString("swmp_device_id") ?? "";
    if (_myId.isEmpty) {
      _myId = "swmp_${Random().nextInt(1000000)}";
      await prefs.setString("swmp_device_id", _myId);
    }

    _myMacAddress = await BluetoothService.instance.getMyAddress();
    if (_myMacAddress.isEmpty) {
      _myMacAddress = _myId;
    } else {
      _myMacAddress = _myMacAddress.toUpperCase();
    }

    // Wi-Fi signaling and WAN connectivity checks are disabled as requested
    // (the app runs strictly via direct local Bluetooth)
    // await _updateLocalIp();
    // _startUdpDiscovery();
    // _startTcpServer();
    // _startAnnounceTimer();
    // _startConnectivityCheck();

    _isInitialized = true;
    _broadcastStatus();
  }

  void updateUsername(String username) {
    _myName = username;
  }

  void toggleWanSimulation(bool enabled, double distanceKm) {
    _isWanSimulated = enabled;
    _simulatedDistance = distanceKm;
    _broadcastStatus();
    _recordSystemLog("WAN Simulator Mode: ${enabled ? 'ENABLED (${distanceKm.toStringAsFixed(0)} km)' : 'DISABLED'}");
  }

  Future<void> _updateLocalIp() async {
    final ip = await _getMyLocalIp();
    if (ip != null && ip != _myIp) {
      _myIp = ip;
      _recordSystemLog("Local Wi-Fi Network Bound to IP: $ip");
      _broadcastStatus();
    }
  }

  Future<String?> _getMyLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print("SignalWeaver: Failed to fetch local IP: $e");
    }
    return null;
  }

  // --- UDP Subnet Discovery ---

  void _startUdpDiscovery() async {
    try {
      _udpSocket?.close();
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8889, reuseAddress: true);
      _udpSocket!.broadcastEnabled = true;
      _isUdpScanning = true;
      
      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket!.receive();
          if (dg != null) {
            final data = utf8.decode(dg.data);
            try {
              final json = jsonDecode(data);
              if (json['type'] == 'swmp_announce') {
                final peerId = json['id'] as String;
                final peerMac = json['mac'] as String;
                final peerName = json['name'] as String;
                final peerIp = json['ip'] as String;
                
                if (peerMac != _myMacAddress && peerIp != _myIp) {
                  _handleDiscoveredPeer(peerMac, peerName, peerIp);
                }
              }
            } catch (_) {}
          }
        }
      });
      _recordSystemLog("Local UDP Multicast Discovery Listener Active on Port 8889");
    } catch (e) {
      _isUdpScanning = false;
      _recordSystemLog("Failed to bind UDP discovery socket: $e");
    }
    _broadcastStatus();
  }

  void _startAnnounceTimer() {
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      await _updateLocalIp();
      if (_myIp.isNotEmpty && _udpSocket != null) {
        final announce = jsonEncode({
          "type": "swmp_announce",
          "id": _myId,
          "mac": _myMacAddress,
          "name": _myName,
          "ip": _myIp,
        });
        final data = utf8.encode(announce);

        // 1. Broad broadcast
        try {
          _udpSocket?.send(data, InternetAddress('255.255.255.255'), 8889);
        } catch (_) {}

        // 2. Interface subnet broadcast
        try {
          final interfaces = await NetworkInterface.list();
          for (var interface in interfaces) {
            for (var addr in interface.addresses) {
              if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
                final parts = addr.address.split('.');
                if (parts.length == 4) {
                  final broadcastIp = "${parts[0]}.${parts[1]}.${parts[2]}.255";
                  _udpSocket?.send(data, InternetAddress(broadcastIp), 8889);
                }
              }
            }
          }
        } catch (_) {}
      }
    });
  }

  void _handleDiscoveredPeer(String peerMac, String peerName, String peerIp) {
    // Save info
    _ipToName[peerIp] = peerName;
    _ipToMac[peerIp] = peerMac;
    _macToIp[peerMac] = peerIp;

    // Connect if not already connected
    if (!_wifiConnections.containsKey(peerIp)) {
      _connectToPeer(peerIp);
    }
  }

  // --- TCP Mesh Sockets ---

  void _startTcpServer() async {
    try {
      _tcpServer?.close();
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, 8890, shared: true);
      _isTcpServerRunning = true;
      _tcpServer!.listen((Socket clientSocket) {
        final peerIp = clientSocket.remoteAddress.address;
        _handleIncomingSocket(clientSocket, peerIp);
      });
      _recordSystemLog("Local Server Socket active, listening on TCP Port 8890");
    } catch (e) {
      _isTcpServerRunning = false;
      _recordSystemLog("Failed to bind TCP server socket: $e");
    }
    _broadcastStatus();
  }

  void _connectToPeer(String peerIp) async {
    try {
      final socket = await Socket.connect(peerIp, 8890, timeout: const Duration(seconds: 3));
      final mac = _ipToMac[peerIp] ?? peerIp;
      final name = _ipToName[peerIp] ?? "Peer";
      
      _wifiConnections[peerIp] = socket;
      _recordSystemLog("TCP Connection established to $name ($peerIp) [Wi-Fi Binding]");
      
      // Send handshake packet containing our MAC and Name
      _sendHandshake(socket);
      _listenToSocket(socket, peerIp);
      _broadcastStatus();
    } catch (_) {
      // Quiet fail on connection retries
    }
  }

  void _handleIncomingSocket(Socket socket, String peerIp) {
    _wifiConnections[peerIp] = socket;
    _recordSystemLog("Accepted incoming TCP connection from peer at $peerIp");
    
    _sendHandshake(socket);
    _listenToSocket(socket, peerIp);
    _broadcastStatus();
  }

  void _sendHandshake(Socket socket) {
    final handshake = jsonEncode({
      "type": "swmp_handshake",
      "mac": _myMacAddress,
      "name": _myName,
    });
    _writeToSocket(socket, 0, handshake); // type 0 is JSON
  }

  void _listenToSocket(Socket socket, String peerIp) {
    final List<int> streamBuffer = [];
    socket.listen(
      (List<int> chunk) {
        streamBuffer.addAll(chunk);
        _processTcpStream(streamBuffer, peerIp);
      },
      onError: (e) {
        _disconnectPeer(peerIp);
      },
      onDone: () {
        _disconnectPeer(peerIp);
      },
      cancelOnError: true,
    );
  }

  void _processTcpStream(List<int> buffer, String peerIp) {
    try {
      while (buffer.length >= 5) {
        // Parse Length header (first 4 bytes)
        final bd = ByteData.sublistView(Uint8List.fromList(buffer.sublist(0, 4)));
        final length = bd.getInt32(0, Endian.big);
        final type = buffer[4]; // 5th byte

        if (buffer.length >= 5 + length) {
          final payloadBytes = buffer.sublist(5, 5 + length);
          buffer.removeRange(0, 5 + length);

          _handleIncomingPayload(payloadBytes, type, peerIp);
        } else {
          // Packet incomplete, wait for next chunks
          break;
        }
      }
    } catch (e) {
      print("SignalWeaver: Stream parsing error: $e");
    }
  }

  void _handleIncomingPayload(List<int> payloadBytes, int type, String peerIp) {
    if (type == 0) {
      // JSON Payload
      final jsonStr = utf8.decode(payloadBytes);
      try {
        final json = jsonDecode(jsonStr);
        if (json['type'] == 'swmp_handshake') {
          final peerMac = json['mac'] as String;
          final peerName = json['name'] as String;
          _ipToMac[peerIp] = peerMac;
          _macToIp[peerMac] = peerIp;
          _ipToName[peerIp] = peerName;
          _recordSystemLog("Handshake completed: IP $peerIp is $peerName ($peerMac)");
          _broadcastStatus();
        } else {
          _onPacketReceived(Map<String, dynamic>.from(json), peerIp);
        }
      } catch (e) {
        print("SignalWeaver: Failed to decode JSON payload: $e");
      }
    }
  }

  void _disconnectPeer(String peerIp) {
    final socket = _wifiConnections.remove(peerIp);
    try {
      socket?.destroy();
    } catch (_) {}
    final name = _ipToName[peerIp] ?? peerIp;
    _recordSystemLog("TCP Connection lost to $name ($peerIp)");
    _broadcastStatus();
  }

  // --- Packet Propagation Routing Engine (SWMP) ---

  Future<void> _onPacketReceived(Map<String, dynamic> packet, String sourceIp) async {
    final packetId = packet['id'] as String? ?? "";
    if (packetId.isEmpty || _seenPacketIds.contains(packetId)) {
      return;
    }
    _seenPacketIds.add(packetId);

    // Reload my address in case it was updated natively
    final resolvedMac = await BluetoothService.instance.getMyAddress();
    if (resolvedMac.isNotEmpty) {
      _myMacAddress = resolvedMac.toUpperCase();
    }

    final recipientId = packet['recipientId'] as String? ?? "";
    final senderName = packet['senderName'] as String? ?? "Peer";
    final type = packet['type'] as String? ?? "text";
    
    // Check if it is meant for this device
    final isGroup = recipientId == 'group_chat' || recipientId.startsWith('group_');
    final isForMe = isGroup || 
                    recipientId.toUpperCase() == _myMacAddress.toUpperCase() || 
                    recipientId.toLowerCase() == "swmp_${_myName.toLowerCase()}_wan";

    if (isForMe) {
      _recordRoutingLog({
        "direction": "incoming",
        "packetId": packetId,
        "sender": senderName,
        "recipient": isGroup ? "Group Chat" : "Me",
        "transport": "Wi-Fi Socket [Mesh]",
        "hops": packet['hopCount'] ?? 0,
        "distance": packet['distance'] ?? 0.0,
        "status": "delivered",
        "timestamp": DateTime.now().millisecondsSinceEpoch,
      });

      // Inject packet into the UI chat stream
      _packetStreamController.add(packet);
    }

    // Forwarding/Flooding to propagate through mesh (Bluetooth only)
    final hopCount = packet['hopCount'] as int? ?? 0;
    final maxHops = packet['maxHops'] as int? ?? 15;

    if (hopCount < maxHops) {
      final List<String> route = List<String>.from(packet['route'] ?? []);
      if (!route.contains(_myMacAddress)) {
        route.add(_myMacAddress);
      }

      final forwardedPacket = Map<String, dynamic>.from(packet);
      forwardedPacket['hopCount'] = hopCount + 1;
      forwardedPacket['route'] = route;

      // Flood to Bluetooth neighbors via MethodChannel
      if (isGroup || recipientId != _myMacAddress) {
        try {
          await BluetoothService.instance.sendMessage(recipientId, jsonEncode(forwardedPacket));
        } catch (_) {}
      }
    }
  }

  Future<bool> routeMessage({
    required String sessionId,
    required String recipientAddress,
    required String body,
    required String type,
    required String senderName,
    String? replyToId,
    String? replyToBody,
    String? replyToSender,
    List<String>? membersList,
  }) async {
    // Reload my address in case it was updated natively
    final resolvedMac = await BluetoothService.instance.getMyAddress();
    if (resolvedMac.isNotEmpty) {
      _myMacAddress = resolvedMac.toUpperCase();
    }

    final packetId = "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(100000)}";
    final isGroup = recipientAddress == 'group_chat' || recipientAddress.startsWith('group_');
    
    final cleanRecipient = recipientAddress.toUpperCase();
    final cleanMyMac = _myMacAddress.toUpperCase();

    final packet = {
      "id": packetId,
      "sessionId": sessionId,
      "recipientAddress": recipientAddress, // legacy support for Kotlin
      "recipientId": recipientAddress,       // SWMP envelope
      "senderName": senderName,
      "senderAddress": cleanMyMac,
      "body": body,
      "type": type,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "replyToId": replyToId,
      "replyToBody": replyToBody,
      "replyToSender": replyToSender,
      "hopCount": 0,
      "maxHops": 1,
      "route": [cleanMyMac],
      "distance": 0.0,
      if (type == "dh_request" || type == "dh_response") "publicKey": body,
      if (type == "message_reaction") "targetMessageId": replyToId,
      if (type == "message_reaction") "reaction": body,
      if (type == "typing") "isTyping": body == "true",
      if (type == "group_create") "members": membersList,
      if (type == "group_create") "groupName": body,
      if (type == "call_invite") "isVideo": body == "true",
    };

    _seenPacketIds.add(packetId);
    bool routedSuccessfully = false;

    if (isGroup) {
      // Send group broadcast over Bluetooth
      await BluetoothService.instance.broadcastMessage(jsonEncode(packet));
      routedSuccessfully = true;
    } else {
      // Send directly to the recipient over Bluetooth
      routedSuccessfully = await BluetoothService.instance.sendMessage(recipientAddress, jsonEncode(packet));
    }

    _recordRoutingLog({
      "direction": "outgoing",
      "packetId": packetId,
      "sender": "Me",
      "recipient": isGroup ? "Group Chat" : (recipientAddress.substring(0, min(8, recipientAddress.length))),
      "transport": "Bluetooth [Direct]",
      "hops": 0,
      "distance": 0.0,
      "status": routedSuccessfully ? "sent" : "failed",
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });

    return routedSuccessfully;
  }

  // --- Network WAN Bridge ---

  Future<bool> _sendPacketOverWanGateway(Map<String, dynamic> packet) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final distance = packet['distance'] as double? ?? _simulatedDistance;
      
      // Query standard httpbin endpoint to simulate/verify WAN traffic route
      final request = await client.postUrl(Uri.parse("https://httpbin.org/post"));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        "gateway": "BlueChat WAN Cloud Relay",
        "distanceKm": distance,
        "packet": packet,
      }));
      
      final response = await request.close();
      if (response.statusCode == 200) {
        _recordSystemLog("Relayed packet through WAN Cloud Gateway successfully (Distance: ${distance.toStringAsFixed(0)} km)");
        
        final recipient = packet['recipientId'] as String;
        final sender = packet['senderName'] as String;
        final body = packet['body'] as String;
        final isBluetoothAddress = recipient.contains(":") || (!recipient.startsWith("swmp_") && recipient.length == 17);
        final isRemote = !_macToIp.containsKey(recipient) && 
                         recipient != _myMacAddress &&
                         !isBluetoothAddress;

        // Simulating the store-and-forward bridge return: in simulation, target receives WAN route packets
        Timer(Duration(milliseconds: 500 + Random().nextInt(1000)), () {
          // If we send to ourselves in distance simulation, trigger incoming response
          if (packet['recipientId'] == _myMacAddress || _macToIp.containsKey(packet['recipientId'])) {
            _onPacketReceived(packet, "127.0.0.1");
          }
        });

        if (isRemote && packet['type'] == 'text') {
          // Trigger a simulated reply from the remote contact (Bob)
          Timer(const Duration(seconds: 2), () {
            DatabaseHelper.instance.getPeer(recipient).then((peer) {
              final peerName = peer?.customName ?? peer?.name ?? "Remote Contact";
              final replyPacket = {
                "id": "sys_reply_${DateTime.now().millisecondsSinceEpoch}",
                "sessionId": recipient,
                "recipientAddress": _myMacAddress,
                "recipientId": _myMacAddress,
                "senderName": peerName,
                "senderAddress": recipient,
                "body": "Hi $sender! I received your message: \"$body\" via SignalWeaver WAN Bridge (Distance: ${distance.toStringAsFixed(0)} km). 🌍⚡",
                "type": "text",
                "timestamp": DateTime.now().millisecondsSinceEpoch,
                "hopCount": 1,
                "maxHops": 15,
                "route": [recipient, "wan_gateway", _myMacAddress],
                "distance": distance,
              };
              _onPacketReceived(replyPacket, "127.0.0.1");
            });
          });
        }
        
        return true;
      }
    } catch (e) {
      _recordSystemLog("WAN Gateway relay failed: Local interface has no cellular/internet link.");
    }
    return false;
  }

  void _startConnectivityCheck() {
    _pingTimer = Timer.periodic(const Duration(seconds: 8), (timer) async {
      try {
        final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 4));
        final isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
        if (isOnline != _isInternetAvailable) {
          _isInternetAvailable = isOnline;
          _broadcastStatus();
          _recordSystemLog("Cellular/WAN network path changed: ${isOnline ? 'ONLINE (WAN Gateways Connected)' : 'OFFLINE (Local Mesh Only)'}");
        }
      } catch (_) {
        if (_isInternetAvailable) {
          _isInternetAvailable = false;
          _broadcastStatus();
          _recordSystemLog("Cellular/WAN network path changed: OFFLINE");
        }
      }
    });
  }

  // --- Helpers ---

  bool _writeToSocket(Socket socket, int type, String data) {
    try {
      final payloadBytes = utf8.encode(data);
      final header = ByteData(5);
      header.setInt32(0, payloadBytes.length, Endian.big);
      header.setUint8(4, type);
      
      socket.add(header.buffer.asUint8List());
      socket.add(payloadBytes);
      socket.flush();
      return true;
    } catch (e) {
      print("SignalWeaver: Socket write failed: $e");
      return false;
    }
  }

  void _recordRoutingLog(Map<String, dynamic> log) {
    _routingLogs.insert(0, log);
    if (_routingLogs.length > 50) {
      _routingLogs.removeLast();
    }
    _logsController.add(List.from(_routingLogs));
  }

  void _recordSystemLog(String message) {
    _recordRoutingLog({
      "direction": "system",
      "packetId": "sys_${DateTime.now().microsecondsSinceEpoch}",
      "sender": "System",
      "recipient": "Log",
      "transport": "Interface Broker",
      "hops": 0,
      "distance": 0.0,
      "status": message,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _broadcastStatus() {
    _statusController.add({
      "isUdpScanning": _isUdpScanning,
      "isTcpServerRunning": _isTcpServerRunning,
      "isInternetAvailable": _isInternetAvailable,
      "isWanSimulated": _isWanSimulated,
      "simulatedDistance": _simulatedDistance,
      "connectedIpsCount": _wifiConnections.length,
      "localIp": _myIp,
      "localMac": _myMacAddress,
    });
  }

  void dispose() {
    _announceTimer?.cancel();
    _pingTimer?.cancel();
    _udpSocket?.close();
    _tcpServer?.close();
    _wifiConnections.values.forEach((socket) => socket.destroy());
    _wifiConnections.clear();
    _logsController.close();
    _packetStreamController.close();
    _statusController.close();
  }
}
