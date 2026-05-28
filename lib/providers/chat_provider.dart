import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import '../database/database_helper.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/bluetooth_peer.dart';
import '../services/bluetooth_service.dart';
import '../services/encryption_service.dart';
import '../services/signal_weaver_service.dart';
import '../services/email_backup_service.dart';

class ChatProvider with ChangeNotifier {
  final BluetoothService _bluetooth = BluetoothService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<BluetoothPeer> _discoveredDevices = [];
  final Map<String, BluetoothPeer> _connectedDevices = {};
  List<ChatSession> _chatSessions = [];
  final Map<String, List<ChatMessage>> _messagesBySession = {};
  
  bool _isScanning = false;
  bool _isServerRunning = false;
  String? _activeSessionId;

  // Typing state
  final Map<String, String> _typingPeers = {};
  final Map<String, Timer> _typingTimers = {};

  String? getTypingStatus(String sessionId) => _typingPeers[sessionId];

  // DH Keys
  String? _myPrivateKeyHex;
  String? _myPublicKeyHex;

  // Call States
  String? _activeCallPeerAddress;
  String? _activeCallPeerName;
  String _callState = 'idle'; // 'idle', 'calling', 'incoming', 'active'
  Timer? _callTimer;
  int _callDuration = 0;
  Timer? _callTimeoutTimer;
  bool _isIncomingCall = false;
  bool _isVideoCall = false;

  final ValueNotifier<Uint8List?> localVideoFrame = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<Uint8List?> remoteVideoFrame = ValueNotifier<Uint8List?>(null);

  // Stream Subscriptions
  StreamSubscription? _discoverySub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _messageSub;
  StreamSubscription? _progressSub;
  StreamSubscription? _swmpSub;

  // Getters
  List<BluetoothPeer> get discoveredDevices => _discoveredDevices;
  List<BluetoothPeer> get connectedDevices => _connectedDevices.values.toList();
  List<ChatSession> get chatSessions => _chatSessions;
  bool get isScanning => _isScanning;
  bool get isServerRunning => _isServerRunning;
  String? get activeSessionId => _activeSessionId;

  String? get activeCallPeerAddress => _activeCallPeerAddress;
  String? get activeCallPeerName => _activeCallPeerName;
  String get callState => _callState;
  int get callDuration => _callDuration;
  bool get isVideoCall => _isVideoCall;

  List<ChatMessage> getMessagesForSession(String sessionId) {
    return _messagesBySession[sessionId] ?? [];
  }

  // --- Initialization ---
  
  Future<void> init() async {
    await loadSessionsFromDb();
    await _loadOrGenerateDHKeys();
    
    // Initialize SignalWeaver Hybrid Services
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'User';
    await SignalWeaverService.instance.init(username);
    
    _startListeningToNativeEvents();
  }

  Future<void> _loadOrGenerateDHKeys() async {
    final prefs = await SharedPreferences.getInstance();
    String? priv = prefs.getString('dh_private_key');
    String? pub = prefs.getString('dh_public_key');
    if (priv == null || pub == null) {
      final privKey = EncryptionService.instance.generatePrivateKey();
      final pubKey = EncryptionService.instance.calculatePublicKey(privKey);
      priv = privKey.toRadixString(16);
      pub = pubKey.toRadixString(16);
      await prefs.setString('dh_private_key', priv);
      await prefs.setString('dh_public_key', pub);
    }
    _myPrivateKeyHex = priv;
    _myPublicKeyHex = pub;
  }

  void setActiveSession(String? sessionId) {
    _activeSessionId = sessionId;
    _bluetooth.setActiveSessionId(sessionId);
    if (sessionId != null) {
      loadMessagesForSession(sessionId);
      _bluetooth.dismissNotification(sessionId);
      _db.markSessionRead(sessionId).then((_) {
        loadSessionsFromDb();
      });
    }
  }

  Future<void> loadSessionsFromDb() async {
    _chatSessions = await _db.getSessions();
    _chatSessions.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.timestamp.compareTo(a.timestamp);
    });
    notifyListeners();
  }

  Future<void> loadMessagesForSession(String sessionId) async {
    final msgs = await _db.getMessages(sessionId);
    final decryptedMsgs = <ChatMessage>[];
    
    for (var msg in msgs) {
      if (msg.type == "encrypted_text") {
        final peer = await _db.getPeer(msg.sessionId);
        if (peer != null && peer.sharedKey != null && peer.sharedKey!.isNotEmpty) {
          try {
            final decryptedBody = EncryptionService.instance.decryptText(msg.body, peer.sharedKey!);
            await _db.updateMessageBodyAndType(msg.id, decryptedBody, "text");
            decryptedMsgs.add(msg.copyWith(
              body: decryptedBody,
              type: "text",
            ));
          } catch (e) {
            print("ChatProvider: Decryption failed for message ${msg.id}: $e");
            decryptedMsgs.add(msg.copyWith(
              body: "[Decryption Failed]",
              type: "text",
            ));
          }
        } else {
          decryptedMsgs.add(msg.copyWith(
            body: "[Encrypted Message - Key Handshake Pending]",
            type: "encrypted_pending",
          ));
        }
      } else {
        decryptedMsgs.add(msg);
      }
    }
    
    _messagesBySession[sessionId] = decryptedMsgs;
    notifyListeners();
  }

  // --- Bluetooth Controls ---

  Future<void> startScan() async {
    _discoveredDevices.clear();
    _isScanning = true;
    notifyListeners();
    
    final success = await _bluetooth.startDiscovery();
    if (!success) {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await _bluetooth.stopDiscovery();
    _isScanning = false;
    notifyListeners();
  }

  Future<void> startServer() async {
    final success = await _bluetooth.startServer();
    if (success) {
      _isServerRunning = true;
      
      final groupSession = ChatSession(
        id: "group_chat",
        name: "Local Broadcast Group",
        isGroup: true,
        lastMessage: "Server active hosting mesh...",
        timestamp: DateTime.now(),
      );
      await _db.insertSession(groupSession);
      await loadSessionsFromDb();
      notifyListeners();
    }
  }

  Future<void> stopServer() async {
    await _bluetooth.stopServer();
    _isServerRunning = false;
    notifyListeners();
  }

  Future<void> connectToDevice(BluetoothPeer peer) async {
    final idx = _discoveredDevices.indexWhere((d) => d.address == peer.address);
    if (idx != -1) {
      _discoveredDevices[idx] = _discoveredDevices[idx].copyWith(connectionState: 'connecting');
      notifyListeners();
    }
    await _bluetooth.connectToDevice(peer.address);
  }

  Future<void> disconnectDevice(String address) async {
    if (_activeCallPeerAddress == address || address.isEmpty) {
      await _bluetooth.stopAudioCall();
      _resetCallState();
    }
    await _bluetooth.disconnect(address);
  }

  void initiateCall(String peerAddress, String peerName, String myUsername, {bool isVideo = false}) async {
    _activeCallPeerAddress = peerAddress;
    _activeCallPeerName = peerName;
    _callState = 'calling';
    _callDuration = 0;
    _isIncomingCall = false;
    _isVideoCall = isVideo;
    localVideoFrame.value = null;
    remoteVideoFrame.value = null;
    notifyListeners();

    _startCallTimeoutTimer();

    if (!_connectedDevices.containsKey(peerAddress)) {
      print("ChatProvider: Peer not connected. Connecting first for call...");
      await _bluetooth.connectToDevice(peerAddress);
    }

    await SignalWeaverService.instance.routeMessage(
      sessionId: peerAddress,
      recipientAddress: peerAddress,
      body: isVideo ? "true" : "false",
      type: "call_invite",
      senderName: myUsername,
    );
  }

  void _startCallTimeoutTimer() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_callState == 'calling' || _callState == 'incoming') {
        print("ChatProvider: Call request timed out.");
        _saveCallSummaryMessage(
          _activeCallPeerAddress ?? "", 
          _activeCallPeerName ?? "Peer", 
          0, 
          _isIncomingCall
        );
        _resetCallState();
      }
    });
  }

  void _saveCallSummaryMessage(String sessionId, String peerName, int duration, bool isIncoming) async {
    final typeLabel = _isVideoCall ? "video call" : "voice call";
    final directionLabel = isIncoming ? "Incoming" : "Outgoing";
    final durationLabel = duration > 0 ? "(${duration}s)" : "(No answer)";
    final summary = "$directionLabel $typeLabel $durationLabel";

    final message = ChatMessage(
      id: _generateMessageId(),
      sessionId: sessionId,
      senderName: "System",
      senderAddress: "",
      body: summary,
      type: "call_summary",
      timestamp: DateTime.now(),
      status: "read",
      isSelf: !isIncoming,
    );
    await _db.insertMessage(message);
    await _db.updateSessionLastMessage(sessionId, summary, message.timestamp.millisecondsSinceEpoch);
    _addMessageToLocalList(sessionId, message);
    await loadSessionsFromDb();
  }

  void acceptCall() async {
    if (_activeCallPeerAddress == null) return;
    final peer = _activeCallPeerAddress!;
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      declineCall();
      return;
    }

    if (_isVideoCall) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        declineCall();
        return;
      }
    }
    
    _callState = 'active';
    _callDuration = 0;
    notifyListeners();

    await _bluetooth.startAudioCall(peer, isVideo: _isVideoCall);
    _startCallTimer();

    await SignalWeaverService.instance.routeMessage(
      sessionId: peer,
      recipientAddress: peer,
      body: "",
      type: "call_accept",
      senderName: "",
    );
  }

  void declineCall() async {
    if (_activeCallPeerAddress == null) return;
    final peer = _activeCallPeerAddress!;
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    _resetCallState();

    await SignalWeaverService.instance.routeMessage(
      sessionId: peer,
      recipientAddress: peer,
      body: "",
      type: "call_decline",
      senderName: "",
    );
  }

  void hangUp() async {
    if (_activeCallPeerAddress == null) return;
    final peer = _activeCallPeerAddress!;
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    _resetCallState();

    await _bluetooth.stopAudioCall();

    await SignalWeaverService.instance.routeMessage(
      sessionId: peer,
      recipientAddress: peer,
      body: "",
      type: "call_hangup",
      senderName: "",
    );
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callDuration++;
      notifyListeners();
    });
  }

  void _resetCallState() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    
    if (_callState == 'active' && _activeCallPeerAddress != null) {
      _saveCallSummaryMessage(_activeCallPeerAddress!, _activeCallPeerName ?? 'Peer', _callDuration, _isIncomingCall);
    }

    _callTimer?.cancel();
    _callTimer = null;

    _activeCallPeerAddress = null;
    _activeCallPeerName = null;
    _callState = 'idle';
    _isVideoCall = false;
    localVideoFrame.value = null;
    remoteVideoFrame.value = null;
    notifyListeners();
  }

  bool _isPhoto(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'gif' || ext == 'webp' || ext == 'bmp';
  }

  bool _isVideo(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return ext == 'mp4' || ext == 'mov' || ext == 'avi' || ext == 'mkv' || ext == 'webm' || ext == '3gp';
  }

  // --- Send Message & File ---

  String _generateMessageId() {
    final rand = Random();
    return "${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(100000)}";
  }

  Future<void> sendTextMessage(
    String sessionId, 
    String body, 
    String senderName, {
    String? replyToId,
    String? replyToBody,
    String? replyToSender,
  }) async {
    final messageId = _generateMessageId();
    final isGroup = sessionId == "group_chat" || sessionId.startsWith("group_");
    
    String status = "sending";
    if (!isGroup) {
      final peer = await _db.getPeer(sessionId);
      if (peer == null || peer.sharedKey == null || peer.sharedKey!.isEmpty) {
        status = "pending_key_exchange";
      }
    }

    final message = ChatMessage(
      id: messageId,
      sessionId: sessionId,
      senderName: senderName,
      senderAddress: "", // Empty for self
      body: body,
      type: "text",
      timestamp: DateTime.now(),
      status: status,
      isSelf: true,
      replyToId: replyToId,
      replyToBody: replyToBody,
      replyToSender: replyToSender,
    );

    await _db.insertMessage(message);
    await _db.updateSessionLastMessage(sessionId, body, message.timestamp.millisecondsSinceEpoch);
    _addMessageToLocalList(sessionId, message);
    await loadSessionsFromDb();

    if (isGroup) {
      String? groupName;
      final sessionIdx = _chatSessions.indexWhere((s) => s.id == sessionId);
      if (sessionIdx != -1) {
        groupName = _chatSessions[sessionIdx].name;
      }

      await SignalWeaverService.instance.routeMessage(
        sessionId: sessionId,
        recipientAddress: sessionId,
        body: body,
        type: "text",
        senderName: senderName,
        replyToId: replyToId,
        replyToBody: replyToBody,
        replyToSender: replyToSender,
      );
    } else {
      if (status == "pending_key_exchange") {
        await _loadOrGenerateDHKeys();
        await SignalWeaverService.instance.routeMessage(
          sessionId: sessionId,
          recipientAddress: sessionId,
          body: _myPublicKeyHex!,
          type: "dh_request",
          senderName: senderName,
        );
      } else {
        final peer = await _db.getPeer(sessionId);
        final encryptedBody = EncryptionService.instance.encryptText(body, peer!.sharedKey!);
        final success = await SignalWeaverService.instance.routeMessage(
          sessionId: sessionId,
          recipientAddress: sessionId,
          body: encryptedBody,
          type: "encrypted_text",
          senderName: senderName,
          replyToId: replyToId,
          replyToBody: replyToBody,
          replyToSender: replyToSender,
        );
        final finalStatus = success ? "sent" : "failed";
        await _db.updateMessageStatus(messageId, finalStatus);
        _updateLocalMessageStatus(sessionId, messageId, finalStatus);
      }
    }
  }

  Future<void> _sendPendingE2EOMessages(String peerAddress, String aesKey) async {
    final msgs = await _db.getMessages(peerAddress);
    for (var msg in msgs) {
      if (msg.status == "pending_key_exchange") {
        final encryptedBody = EncryptionService.instance.encryptText(msg.body, aesKey);
        final success = await SignalWeaverService.instance.routeMessage(
          sessionId: peerAddress,
          recipientAddress: peerAddress,
          body: encryptedBody,
          type: "encrypted_text",
          senderName: msg.senderName,
        );
        final finalStatus = success ? "sent" : "failed";
        await _db.updateMessageStatus(msg.id, finalStatus);
        _updateLocalMessageStatus(peerAddress, msg.id, finalStatus);
      }
    }
    await loadSessionsFromDb();
  }

  Future<void> sendFileMessage({
    required String sessionId,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String senderName,
    String? replyToId,
    String? replyToBody,
    String? replyToSender,
  }) async {
    final messageId = _generateMessageId();
    
    final message = ChatMessage(
      id: messageId,
      sessionId: sessionId,
      senderName: senderName,
      senderAddress: "",
      body: fileName,
      type: "file",
      filePath: filePath,
      fileSize: fileSize,
      timestamp: DateTime.now(),
      status: "sending",
      isSelf: true,
      replyToId: replyToId,
      replyToBody: replyToBody,
      replyToSender: replyToSender,
    );

    await _db.insertMessage(message);
    await _db.updateSessionLastMessage(sessionId, "📁 $fileName", message.timestamp.millisecondsSinceEpoch);
    _addMessageToLocalList(sessionId, message);
    await loadSessionsFromDb();

    final success = await _bluetooth.sendFile(
      address: sessionId,
      filePath: filePath,
      fileId: messageId,
      fileName: fileName,
      fileSize: fileSize,
      senderName: senderName,
    );

    if (!success) {
      await _db.updateMessageStatus(messageId, "failed");
      _updateLocalMessageStatus(sessionId, messageId, "failed");
    }
  }

  void _addMessageToLocalList(String sessionId, ChatMessage msg) {
    if (!_messagesBySession.containsKey(sessionId)) {
      _messagesBySession[sessionId] = [];
    }
    _messagesBySession[sessionId]!.add(msg);
    notifyListeners();
  }

  void _updateLocalMessageStatus(String sessionId, String messageId, String status) {
    final list = _messagesBySession[sessionId];
    if (list != null) {
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(status: status);
      }
    }
  }

  // --- Stream Listening Logic ---

  void _startListeningToNativeEvents() {
    // 1. Discovery Stream
    _discoverySub = _bluetooth.discoveryStream.listen((event) {
      final type = event["type"] as String;
      if (type == "discoveryStarted") {
        _isScanning = true;
        _discoveredDevices.clear();
        notifyListeners();
      } else if (type == "discoveryFinished") {
        _isScanning = false;
        notifyListeners();
      } else if (type == "deviceFound") {
        final deviceMap = Map<String, dynamic>.from(event["device"]);
        final peer = BluetoothPeer.fromMap(deviceMap);
        
        if (!_discoveredDevices.any((d) => d.address == peer.address)) {
          _discoveredDevices.add(peer);
          notifyListeners();
        }
      }
    });

    // 2. Connection State Stream
    _connectionSub = _bluetooth.connectionStream.listen((event) async {
      final state = event["state"] as String;
      final address = event["address"] as String;
      final name = event["name"] as String;

      final peer = BluetoothPeer(
        name: name,
        address: address,
        isBonded: false,
        connectionState: state,
      );

      if (state == "connected") {
        _connectedDevices[address] = peer;
        await _db.insertOrUpdatePeer(peer);
        
        final session = ChatSession(
          id: address,
          name: name,
          isGroup: false,
          lastMessage: "Connected",
          timestamp: DateTime.now(),
        );
        await _db.insertSession(session);
        await loadSessionsFromDb();
      } else if (state == "disconnected" || state == "failed") {
        _connectedDevices.remove(address);
        await _db.updateSessionLastMessage(
          address, 
          state == "failed" ? "Connection failed" : "Disconnected", 
          DateTime.now().millisecondsSinceEpoch
        );
        await loadSessionsFromDb();
      }

      final idx = _discoveredDevices.indexWhere((d) => d.address == address);
      if (idx != -1) {
        _discoveredDevices[idx] = _discoveredDevices[idx].copyWith(connectionState: state);
      }
      notifyListeners();
    });

    // 3. Messages Stream (Bluetooth Native & ACKs)
    _messageSub = _bluetooth.messageStream.listen((event) async {
      final String? eventType = event["type"] as String?;
      
      // Video call framing bypass
      if (eventType == "videoFrame") {
        final isLocal = event["isLocal"] as bool? ?? false;
        final data = event["data"] as Uint8List?;
        if (isLocal) {
          localVideoFrame.value = data;
        } else {
          remoteVideoFrame.value = data;
        }
        return;
      }

      // Outgoing status change (e.g. delivered ACK from remote peer)
      if (eventType == "messageStatusChanged") {
        final messageId = event["messageId"] as String;
        final status = event["status"] as String;
        final sessionId = event["sessionId"] as String;
        
        await _db.updateMessageStatus(messageId, status);
        _updateLocalMessageStatus(sessionId, messageId, status);
        notifyListeners();
        return;
      }

      // WriteThread triggers
      if (eventType == "sendSuccess") {
        final messageId = event["messageId"] as String;
        final sessionId = event["sessionId"] as String;
        await _db.updateMessageStatus(messageId, "sent");
        _updateLocalMessageStatus(sessionId, messageId, "sent");
        notifyListeners();
        return;
      }

      if (eventType == "sendFailure") {
        final messageId = event["messageId"] as String;
        final sessionId = event["sessionId"] as String;
        await _db.updateMessageStatus(messageId, "failed");
        _updateLocalMessageStatus(sessionId, messageId, "failed");
        notifyListeners();
        return;
      }

      // Parse normal incoming messages
      try {
        print("ChatProvider: Received Bluetooth native message event: $event");
        final messageJsonString = event["message"] as String;
        final Map<String, dynamic> data = jsonDecode(messageJsonString);
        final senderAddress = (event["senderAddress"] as String?) ?? (data["senderAddress"] as String?) ?? "";
        
        await _handleIncomingMessageMap(data, senderAddress);
      } catch (e) {
        print("ChatProvider: Error processing native message event: $e");
      }
    });

    // 3b. Messages Stream (SignalWeaver Wi-Fi/WAN Mesh - fallback)
    _swmpSub = SignalWeaverService.instance.packetStream.listen((packet) async {
      try {
        print("ChatProvider: Received SignalWeaver mesh message packet: $packet");
        final senderAddress = packet["senderAddress"] as String? ?? "";
        await _handleIncomingMessageMap(packet, senderAddress);
      } catch (e) {
        print("ChatProvider: Error processing SignalWeaver mesh packet: $e");
      }
    });

    // 4. File Transfer Progress Stream
    _progressSub = _bluetooth.progressStream.listen((event) async {
      final fileId = event["fileId"] as String;
      final progress = (event["progress"] as num).toInt();
      final total = (event["total"] as num).toInt();
      final speed = (event["speed"] as num).toDouble();
      final status = event["status"] as String; 
      final errorOrPath = event["errorOrPath"] as String;

      for (var sessionId in _messagesBySession.keys) {
        final list = _messagesBySession[sessionId]!;
        final idx = list.indexWhere((m) => m.id == fileId);
        if (idx != -1) {
          final current = list[idx];
          
          double progressPct = 0.0;
          if (total > 0) {
            progressPct = progress / total;
          }

          if (status == "success" && errorOrPath.isNotEmpty) {
            // Update to save the downloaded file path
            await _db.updateMessageFilePath(fileId, errorOrPath);
            await _db.updateMessageStatus(fileId, "read");
            list[idx] = current.copyWith(status: "read", filePath: errorOrPath);
          } else if (status == "failed") {
            await _db.updateMessageStatus(fileId, "failed");
            list[idx] = current.copyWith(status: "failed");
          } else {
            // Just updating transient loading state is enough (handled in UI)
          }
          notifyListeners();
          break;
        }
      }
    });
  }

  Future<void> _handleIncomingMessageMap(Map<String, dynamic> data, String senderAddress) async {
    final sessionId = data["sessionId"] as String? ?? senderAddress;
    final senderName = (data["senderName"] as String?) ?? "Peer";
    final body = data["body"] as String? ?? "";
    final type = data["type"] as String? ?? "text";
    final timestampVal = data["timestamp"];
    final timestamp = timestampVal is int ? DateTime.fromMillisecondsSinceEpoch(timestampVal) : DateTime.now();

    final isGroup = sessionId == "group_chat" || sessionId.startsWith("group_");
    final actualSessionId = isGroup 
        ? sessionId 
        : (senderAddress.isNotEmpty ? senderAddress : sessionId);

    if (type == "typing") {
      _typingPeers[actualSessionId] = senderName;
      notifyListeners();

      _typingTimers[actualSessionId]?.cancel();
      _typingTimers[actualSessionId] = Timer(const Duration(seconds: 4), () {
        _typingPeers.remove(actualSessionId);
        notifyListeners();
      });
      return;
    }

    if (type == "call_invite") {
      print("ChatProvider: Received Call Invite from $senderAddress");
      _isVideoCall = data["isVideo"] == true;
      _activeCallPeerAddress = senderAddress;
      _activeCallPeerName = senderName;
      _callState = 'incoming';
      _isIncomingCall = true;
      _callDuration = 0;
      notifyListeners();
      _startCallTimeoutTimer();
      return;
    }

    if (type == "call_accept") {
      print("ChatProvider: Call Accepted by $senderAddress");
      if (_callState == "calling" && _activeCallPeerAddress == senderAddress) {
        _callTimeoutTimer?.cancel();
        _callTimeoutTimer = null;
        _callState = 'active';
        _callDuration = 0;
        notifyListeners();
        await _bluetooth.startAudioCall(senderAddress, isVideo: _isVideoCall);
        _startCallTimer();
      }
      return;
    }

    if (type == "call_decline") {
      print("ChatProvider: Call Declined by $senderAddress");
      if (_activeCallPeerAddress == senderAddress) {
        _resetCallState();
      }
      return;
    }

    if (type == "call_hangup") {
      print("ChatProvider: Call Hung Up by $senderAddress");
      if (_activeCallPeerAddress == senderAddress) {
        await _bluetooth.stopAudioCall();
        _resetCallState();
      }
      return;
    }

    if (type == "group_create") {
      final groupName = data["groupName"] as String? ?? "Group Chat";
      final membersList = List<String>.from(data["members"] ?? []);
      
      final session = ChatSession(
        id: sessionId,
        name: groupName,
        isGroup: true,
        lastMessage: "Group created by $senderName",
        timestamp: timestamp,
        members: membersList,
      );
      await _db.insertSession(session);
      
      final systemMessage = ChatMessage(
        id: _generateMessageId(),
        sessionId: sessionId,
        senderName: "System",
        senderAddress: "",
        body: "You were added to group \"$groupName\" by $senderName",
        type: "system",
        timestamp: timestamp,
        status: "read",
        isSelf: false,
      );
      await _db.insertMessage(systemMessage);
      await loadSessionsFromDb();
      _addMessageToLocalList(sessionId, systemMessage);
      return;
    }

    if (type == "connection_request") {
      print("ChatProvider: Automatically accepting Connection Request from $senderAddress");
      var peer = await _db.getPeer(senderAddress);
      if (peer == null) {
        peer = BluetoothPeer(
          name: senderName,
          address: senderAddress,
          isBonded: false,
          profileColor: 'FF10B981',
          avatarInitials: senderName.isNotEmpty ? senderName[0].toUpperCase() : 'R',
          connectionStatus: 'approved',
        );
        await _db.insertOrUpdatePeer(peer);
      }
      await acceptConnectionRequest(senderAddress, senderName);
      return;
    }

    if (type == "connection_accept") {
      print("ChatProvider: Processing Connection Accept from $senderAddress");
      await _db.updatePeerConnectionStatus(senderAddress, 'approved');
      await _db.updateSessionLastMessage(senderAddress, "Connection request accepted", DateTime.now().millisecondsSinceEpoch);
      
      final systemMsg = ChatMessage(
        id: "sys_${DateTime.now().millisecondsSinceEpoch}",
        sessionId: senderAddress,
        senderName: "System",
        senderAddress: "",
        body: "Connection accepted! You can now chat securely. 🌍",
        type: "system",
        timestamp: DateTime.now(),
        status: "read",
        isSelf: false,
      );
      await _db.insertMessage(systemMsg);
      await loadSessionsFromDb();
      _addMessageToLocalList(senderAddress, systemMsg);
      return;
    }

    if (type == "connection_decline") {
      print("ChatProvider: Processing Connection Decline from $senderAddress");
      await _db.updatePeerConnectionStatus(senderAddress, 'none');
      await _db.updateSessionLastMessage(senderAddress, "Connection request declined", DateTime.now().millisecondsSinceEpoch);
      
      final systemMsg = ChatMessage(
        id: "sys_${DateTime.now().millisecondsSinceEpoch}",
        sessionId: senderAddress,
        senderName: "System",
        senderAddress: "",
        body: "Connection request was declined.",
        type: "system",
        timestamp: DateTime.now(),
        status: "read",
        isSelf: false,
      );
      await _db.insertMessage(systemMsg);
      await loadSessionsFromDb();
      _addMessageToLocalList(senderAddress, systemMsg);
      return;
    }

    if (type == "dh_request") {
      print("ChatProvider: Processing DH Request from $senderAddress");
      final peerPublicKeyHex = body;
      final peerPublicKey = BigInt.parse(peerPublicKeyHex, radix: 16);
      
      await _loadOrGenerateDHKeys();
      final myPrivateKey = BigInt.parse(_myPrivateKeyHex!, radix: 16);
      final sharedSecret = EncryptionService.instance.calculateSharedSecret(peerPublicKey, myPrivateKey);
      final aesKey = sha256.convert(sharedSecret.toRadixString(16).codeUnits).toString();
      
      await _db.updatePeerSharedKey(senderAddress, aesKey);
      
      await SignalWeaverService.instance.routeMessage(
        sessionId: senderAddress,
        recipientAddress: senderAddress,
        body: _myPublicKeyHex!,
        type: "dh_response",
        senderName: "",
      );
      await _sendPendingE2EOMessages(senderAddress, aesKey);
      return;
    }

    if (type == "dh_response") {
      print("ChatProvider: Processing DH Response from $senderAddress");
      final peerPublicKeyHex = body;
      final peerPublicKey = BigInt.parse(peerPublicKeyHex, radix: 16);
      
      await _loadOrGenerateDHKeys();
      final myPrivateKey = BigInt.parse(_myPrivateKeyHex!, radix: 16);
      final sharedSecret = EncryptionService.instance.calculateSharedSecret(peerPublicKey, myPrivateKey);
      final aesKey = sha256.convert(sharedSecret.toRadixString(16).codeUnits).toString();
      
      await _db.updatePeerSharedKey(senderAddress, aesKey);
      await _sendPendingE2EOMessages(senderAddress, aesKey);
      return;
    }

    String lastMsgText = body;
    String actualBody = body;
    String actualType = type;

    if (type == "encrypted_text") {
      final peer = await _db.getPeer(senderAddress);
      if (peer != null && peer.sharedKey != null && peer.sharedKey!.isNotEmpty) {
        try {
          actualBody = EncryptionService.instance.decryptText(body, peer.sharedKey!);
          actualType = "text";
          lastMsgText = actualBody;
        } catch (e) {
          print("ChatProvider: Decryption failed for incoming message: $e");
          actualBody = "[Decryption Failed]";
          actualType = "text";
          lastMsgText = "[Decryption Failed]";
        }
      } else {
        actualType = "encrypted_text";
        lastMsgText = "[Encrypted Message]";
        
        await _loadOrGenerateDHKeys();
        await SignalWeaverService.instance.routeMessage(
          sessionId: senderAddress,
          recipientAddress: senderAddress,
          body: _myPublicKeyHex!,
          type: "dh_request",
          senderName: "",
        );
      }
    } else if (type == "file") {
      lastMsgText = "📁 $body";
    }

    final replyToId = data["replyToId"] as String?;
    final replyToBody = data["replyToBody"] as String?;
    final replyToSender = data["replyToSender"] as String?;

    final message = ChatMessage(
      id: data["id"] as String? ?? _generateMessageId(),
      sessionId: actualSessionId,
      senderName: senderName,
      senderAddress: senderAddress,
      body: actualBody,
      type: actualType,
      filePath: data["filePath"] as String?,
      fileSize: data["fileSize"] is num ? (data["fileSize"] as num).toInt() : null,
      timestamp: timestamp,
      status: "read",
      isSelf: false,
      replyToId: replyToId,
      replyToBody: replyToBody,
      replyToSender: replyToSender,
    );

    final session = ChatSession(
      id: actualSessionId,
      name: isGroup 
          ? (actualSessionId == "group_chat" ? "Local Broadcast Group" : (data["groupName"] as String? ?? "Group Chat"))
          : senderName,
      isGroup: isGroup,
      lastMessage: lastMsgText,
      timestamp: message.timestamp,
    );
    await _db.insertSession(session);
    await _db.insertMessage(message);
    await _db.updateSessionLastMessage(actualSessionId, lastMsgText, message.timestamp.millisecondsSinceEpoch);
    
    _addMessageToLocalList(actualSessionId, message);
    await loadSessionsFromDb();
  }

  Future<void> setSessionWallpaper(String sessionId, String? wallpaperPath) async {
    await _db.updateSessionWallpaper(sessionId, wallpaperPath);
    final idx = _chatSessions.indexWhere((s) => s.id == sessionId);
    if (idx != -1) {
      _chatSessions[idx] = _chatSessions[idx].copyWith(wallpaper: wallpaperPath);
    }
    notifyListeners();
  }

  Future<void> updatePeerCustomName(String address, String? customName) async {
    await _db.updatePeerCustomName(address, customName);
    final sessionIdx = _chatSessions.indexWhere((s) => s.id == address);
    if (sessionIdx != -1 && !_chatSessions[sessionIdx].isGroup) {
      final peer = await _db.getPeer(address);
      if (peer != null) {
        _chatSessions[sessionIdx] = _chatSessions[sessionIdx].copyWith(name: customName ?? peer.name);
      }
    }
    notifyListeners();
  }

  Future<void> updatePeerProfilePhoto(String address, String? photoPath) async {
    await _db.updatePeerProfilePhoto(address, photoPath);
    notifyListeners();
  }

  Future<BluetoothPeer?> getPeerInfo(String address) async {
    return await _db.getPeer(address);
  }

  Future<void> toggleMessageReaction(String sessionId, String messageId, String? reaction, String senderName) async {
    await _db.updateMessageReaction(messageId, reaction);
    await SignalWeaverService.instance.routeMessage(
      sessionId: sessionId,
      recipientAddress: sessionId,
      body: reaction ?? "",
      type: "message_reaction",
      senderName: senderName,
      replyToId: messageId,
    );
  }

  Future<void> createGroup(String groupName, List<String> memberAddresses, String myUsername) async {
    final groupId = "group_${DateTime.now().millisecondsSinceEpoch}";
    final myAddress = await _bluetooth.getMyAddress();
    final membersList = [if (myAddress.isNotEmpty) myAddress, ...memberAddresses];

    final session = ChatSession(
      id: groupId,
      name: groupName,
      isGroup: true,
      lastMessage: "Group created",
      timestamp: DateTime.now(),
      members: membersList,
    );
    await _db.insertSession(session);
    await loadSessionsFromDb();

    final systemMessage = ChatMessage(
      id: _generateMessageId(),
      sessionId: groupId,
      senderName: "System",
      senderAddress: "",
      body: "Group \"$groupName\" created.",
      type: "system",
      timestamp: DateTime.now(),
      status: "read",
      isSelf: true,
    );
    await _db.insertMessage(systemMessage);
    _addMessageToLocalList(groupId, systemMessage);

    await SignalWeaverService.instance.routeMessage(
      sessionId: groupId,
      recipientAddress: groupId,
      body: groupName,
      type: "group_create",
      senderName: myUsername,
      membersList: membersList,
    );
  }

  Future<void> sendTypingStatus(String sessionId, bool isTyping, String senderName) async {
    await SignalWeaverService.instance.routeMessage(
      sessionId: sessionId,
      recipientAddress: sessionId,
      body: isTyping ? "true" : "false",
      type: "typing",
      senderName: senderName,
    );
  }

  Future<void> backupDatabaseToGmail(String gmailAccount) async {
    final dbFile = File(await _db.getDatabasePath());
    if (!dbFile.existsSync()) {
      throw Exception("Database file does not exist");
    }

    final tempDir = Directory.systemTemp;
    final backupFile = File(join(tempDir.path, "bluechat_backup.enc"));
    
    final dbBytes = await dbFile.readAsBytes();
    final encBytes = EncryptionService.instance.encryptBytes(dbBytes, "backup_key_12345");
    await backupFile.writeAsBytes(encBytes);

    if (gmailAccount.isNotEmpty) {
      await EmailBackupService.instance.sendBackupEmail(gmailAccount, backupFile);
    }
  }

  Future<void> restoreDatabaseFromGmail(String gmailAccount) async {
    final tempDir = Directory.systemTemp;
    final backupFile = File(join(tempDir.path, "bluechat_backup_download.enc"));
    
    await EmailBackupService.instance.downloadBackupEmail(gmailAccount, backupFile);
    
    if (!backupFile.existsSync()) {
      throw Exception("Backup file download failed");
    }

    final encBytes = await backupFile.readAsBytes();
    final dbBytes = EncryptionService.instance.decryptBytes(encBytes, "backup_key_12345");
    
    final dbFile = File(await _db.getDatabasePath());
    await _db.closeDb();
    await dbFile.writeAsBytes(dbBytes);
    await _db.initDb();
    await loadSessionsFromDb();
  }

  Future<void> sendConnectionRequest({required String peerAddress, required String peerName}) async {
    final cleanId = peerAddress.trim();
    final cleanName = peerName.trim();

    var peer = await _db.getPeer(cleanId);
    if (peer == null) {
      peer = BluetoothPeer(
        name: cleanName,
        address: cleanId,
        isBonded: false,
        profileColor: 'FF3B82F6',
        avatarInitials: cleanName.isNotEmpty ? cleanName[0].toUpperCase() : 'R',
        connectionStatus: 'pending_sent',
      );
      await _db.insertOrUpdatePeer(peer);
    } else {
      await _db.updatePeerConnectionStatus(cleanId, 'pending_sent');
    }

    final session = ChatSession(
      id: cleanId,
      name: cleanName,
      isGroup: false,
      lastMessage: "Connection request sent...",
      timestamp: DateTime.now(),
    );
    await _db.insertSession(session);
    await loadSessionsFromDb();

    final myProfile = await SharedPreferences.getInstance();
    final myUsername = myProfile.getString('username') ?? 'Peer';
    
    await SignalWeaverService.instance.routeMessage(
      sessionId: cleanId,
      recipientAddress: cleanId,
      body: myUsername,
      type: "connection_request",
      senderName: myUsername,
    );

    Timer(const Duration(seconds: 4), () async {
      final currentPeer = await _db.getPeer(cleanId);
      if (currentPeer != null && currentPeer.connectionStatus == 'pending_sent') {
        await _handleIncomingMessageMap({
          "id": "sys_acc_${DateTime.now().millisecondsSinceEpoch}",
          "sessionId": cleanId,
          "senderAddress": cleanId,
          "senderName": cleanName,
          "body": "Approved",
          "type": "connection_accept",
          "timestamp": DateTime.now().millisecondsSinceEpoch,
        }, cleanId);
      }
    });
  }

  Future<void> acceptConnectionRequest(String peerAddress, String peerName) async {
    final cleanId = peerAddress.trim();
    final cleanName = peerName.trim();

    await _db.updatePeerConnectionStatus(cleanId, 'approved');
    
    final systemMsg = ChatMessage(
      id: "sys_${DateTime.now().millisecondsSinceEpoch}",
      sessionId: cleanId,
      senderName: "System",
      senderAddress: "",
      body: "Connection accepted! You can now chat securely. 🌍",
      type: "system",
      timestamp: DateTime.now(),
      status: "read",
      isSelf: false,
    );
    await _db.insertMessage(systemMsg);
    _addMessageToLocalList(cleanId, systemMsg);

    await _db.updateSessionLastMessage(cleanId, "Connection request accepted", DateTime.now().millisecondsSinceEpoch);
    await loadSessionsFromDb();

    final myProfile = await SharedPreferences.getInstance();
    final myUsername = myProfile.getString('username') ?? 'Peer';

    await SignalWeaverService.instance.routeMessage(
      sessionId: cleanId,
      recipientAddress: cleanId,
      body: myUsername,
      type: "connection_accept",
      senderName: myUsername,
    );
  }

  Future<void> declineConnectionRequest(String peerAddress) async {
    final cleanId = peerAddress.trim();

    await _db.updatePeerConnectionStatus(cleanId, 'none');

    final systemMsg = ChatMessage(
      id: "sys_${DateTime.now().millisecondsSinceEpoch}",
      sessionId: cleanId,
      senderName: "System",
      senderAddress: "",
      body: "Connection request was declined.",
      type: "system",
      timestamp: DateTime.now(),
      status: "read",
      isSelf: false,
    );
    await _db.insertMessage(systemMsg);
    _addMessageToLocalList(cleanId, systemMsg);

    await _db.updateSessionLastMessage(cleanId, "Connection request declined", DateTime.now().millisecondsSinceEpoch);
    await loadSessionsFromDb();

    final myProfile = await SharedPreferences.getInstance();
    final myUsername = myProfile.getString('username') ?? 'Peer';

    await SignalWeaverService.instance.routeMessage(
      sessionId: cleanId,
      recipientAddress: cleanId,
      body: myUsername,
      type: "connection_decline",
      senderName: myUsername,
    );
  }

  Future<void> simulateIncomingRequest({required String peerAddress, required String peerName}) async {
    final cleanId = peerAddress.trim();
    final cleanName = peerName.trim();

    await _handleIncomingMessageMap({
      "id": "sys_req_${DateTime.now().millisecondsSinceEpoch}",
      "sessionId": cleanId,
      "senderAddress": cleanId,
      "senderName": cleanName,
      "body": "Connect request",
      "type": "connection_request",
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    }, cleanId);
  }

  Future<void> toggleSessionPin(String sessionId) async {
    final idx = _chatSessions.indexWhere((s) => s.id == sessionId);
    if (idx != -1) {
      final currentPin = _chatSessions[idx].isPinned;
      await _db.updateSessionPin(sessionId, !currentPin);
      await loadSessionsFromDb();
    }
  }

  Future<void> toggleSessionMute(String sessionId) async {
    final idx = _chatSessions.indexWhere((s) => s.id == sessionId);
    if (idx != -1) {
      final currentMute = _chatSessions[idx].isMuted;
      await _db.updateSessionMute(sessionId, !currentMute);
      await loadSessionsFromDb();
    }
  }

  Future<void> clearHistory(String sessionId) async {
    await _db.clearChatHistory(sessionId);
    _messagesBySession[sessionId]?.clear();
    await loadSessionsFromDb();
    notifyListeners();
  }

  Future<void> deleteMessage(String sessionId, String messageId) async {
    await _db.deleteMessage(messageId);
    _messagesBySession[sessionId]?.removeWhere((m) => m.id == messageId);
    final messages = _messagesBySession[sessionId] ?? [];
    String lastMsgText = "No messages";
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    if (messages.isNotEmpty) {
      final lastMsg = messages.last;
      lastMsgText = lastMsg.type == "file" ? "📁 ${lastMsg.body}" : lastMsg.body;
      timestamp = lastMsg.timestamp.millisecondsSinceEpoch;
    }
    await _db.updateSessionLastMessage(sessionId, lastMsgText, timestamp);
    await loadSessionsFromDb();
    notifyListeners();
  }

  Future<void> addRemoteContact(String name, String address) async {
    final cleanId = address.trim();
    final cleanName = name.trim();

    var peer = BluetoothPeer(
      name: cleanName,
      address: cleanId,
      isBonded: false,
      profileColor: 'FF0D9488', // Teal color for WAN
      avatarInitials: cleanName.isNotEmpty ? cleanName[0].toUpperCase() : 'R',
      connectionStatus: 'approved',
    );
    await _db.insertOrUpdatePeer(peer);

    final session = ChatSession(
      id: cleanId,
      name: cleanName,
      isGroup: false,
      lastMessage: "Remote contact added via QR",
      timestamp: DateTime.now(),
    );
    await _db.insertSession(session);
    await loadSessionsFromDb();
  }

  Future<String> exportBackupData() async {
    final db = await _db.database;
    final sessions = await db.query('sessions');
    final messages = await db.query('messages');
    final peers = await db.query('peers');
    
    final data = {
      'sessions': sessions,
      'messages': messages,
      'peers': peers,
    };
    return jsonEncode(data);
  }

  Future<File> performLocalBackup(String gmailAccount) async {
    final dbPath = await _db.getDatabasePath();
    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      throw Exception("Database file not found");
    }
    final dbBytes = await dbFile.readAsBytes();
    final encBytes = EncryptionService.instance.encryptBytes(dbBytes, "backup_key_12345");
    
    final tempDir = Directory.systemTemp;
    final backupFile = File(join(tempDir.path, "bluechat_backup.enc"));
    await backupFile.writeAsBytes(encBytes);
    return backupFile;
  }

  Future<void> performRestoreFromFile(File file, String gmailAccount) async {
    if (!file.existsSync()) {
      throw Exception("Selected file does not exist");
    }
    final encBytes = await file.readAsBytes();
    final dbBytes = EncryptionService.instance.decryptBytes(encBytes, "backup_key_12345");
    
    final dbPath = await _db.getDatabasePath();
    final dbFile = File(dbPath);
    await _db.closeDb();
    await dbFile.writeAsBytes(dbBytes);
    await _db.initDb();
    await loadSessionsFromDb();
  }

  Future<void> performLocalRestore(String gmailAccount) async {
    final tempDir = Directory.systemTemp;
    final backupFile = File(join(tempDir.path, "bluechat_backup.enc"));
    await performRestoreFromFile(backupFile, gmailAccount);
  }

  @override
  void dispose() {
    _typingTimers.values.forEach((timer) => timer.cancel());
    _typingTimers.clear();
    _discoverySub?.cancel();
    _connectionSub?.cancel();
    _messageSub?.cancel();
    _progressSub?.cancel();
    _swmpSub?.cancel();
    super.dispose();
  }
}
