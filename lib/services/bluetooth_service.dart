import 'dart:async';
import 'package:flutter/services.dart';

class BluetoothService {
  static const MethodChannel _methodChannel = MethodChannel('com.example.bluechat/methods');
  
  static const EventChannel _discoveryEventChannel = EventChannel('com.example.bluechat/events/discovery');
  static const EventChannel _connectionEventChannel = EventChannel('com.example.bluechat/events/connection');
  static const EventChannel _messagesEventChannel = EventChannel('com.example.bluechat/events/messages');
  static const EventChannel _progressEventChannel = EventChannel('com.example.bluechat/events/progress');

  BluetoothService._privateConstructor();
  static final BluetoothService instance = BluetoothService._privateConstructor();

  // --- Stream Getters with detailed debug logging ---
  
  Stream<Map<String, dynamic>> get discoveryStream {
    return _discoveryEventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      print("BlueChat [Transport LOG]: Discovery stream event: $map");
      return map;
    });
  }

  Stream<Map<String, dynamic>> get connectionStream {
    return _connectionEventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      print("BlueChat [Transport LOG]: Connection stream event: $map");
      return map;
    });
  }

  Stream<Map<String, dynamic>> get messageStream {
    return _messagesEventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      print("BlueChat [Transport LOG]: Message stream event: $map");
      return map;
    });
  }

  Stream<Map<String, dynamic>> get progressStream {
    return _progressEventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      print("BlueChat [Transport LOG]: Progress stream event: $map");
      return map;
    });
  }

  // --- Method Invocation with Detailed Debug Logging ---

  Future<bool> startBluetoothService() async {
    print("BlueChat [Transport LOG]: Invoking startBluetoothService...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('startBluetoothService');
      print("BlueChat [Transport LOG]: startBluetoothService result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: startBluetoothService failed: ${e.message}");
      return false;
    }
  }

  Future<bool> checkBluetoothPermission() async {
    print("BlueChat [Transport LOG]: Invoking checkBluetoothPermission...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('checkBluetoothPermission');
      print("BlueChat [Transport LOG]: checkBluetoothPermission result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: checkBluetoothPermission failed: ${e.message}");
      return false;
    }
  }

  Future<bool> startDiscovery() async {
    print("BlueChat [Transport LOG]: Invoking startDiscovery...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('startDiscovery');
      print("BlueChat [Transport LOG]: startDiscovery result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: startDiscovery failed: ${e.message}");
      return false;
    }
  }

  Future<bool> stopDiscovery() async {
    print("BlueChat [Transport LOG]: Invoking stopDiscovery...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('stopDiscovery');
      print("BlueChat [Transport LOG]: stopDiscovery result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: stopDiscovery failed: ${e.message}");
      return false;
    }
  }

  Future<bool> startServer() async {
    print("BlueChat [Transport LOG]: Invoking startServer...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('startServer');
      print("BlueChat [Transport LOG]: startServer result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: startServer failed: ${e.message}");
      return false;
    }
  }

  Future<bool> stopServer() async {
    print("BlueChat [Transport LOG]: Invoking stopServer...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('stopServer');
      print("BlueChat [Transport LOG]: stopServer result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: stopServer failed: ${e.message}");
      return false;
    }
  }

  Future<bool> connectToDevice(String address) async {
    print("BlueChat [Transport LOG]: Invoking connectToDevice to address: $address...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('connectToDevice', {'address': address});
      print("BlueChat [Transport LOG]: connectToDevice result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: connectToDevice failed: ${e.message}");
      return false;
    }
  }

  Future<bool> disconnect(String address) async {
    print("BlueChat [Transport LOG]: Invoking disconnect from address: $address...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('disconnect', {'address': address});
      print("BlueChat [Transport LOG]: disconnect result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: disconnect failed: ${e.message}");
      return false;
    }
  }

  Future<bool> disconnectAll() async {
    print("BlueChat [Transport LOG]: Invoking disconnectAll...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('disconnectAll');
      print("BlueChat [Transport LOG]: disconnectAll result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: disconnectAll failed: ${e.message}");
      return false;
    }
  }

  Future<bool> sendMessage(String address, String messageJson) async {
    print("BlueChat [Transport LOG]: Invoking sendMessage to $address with data: $messageJson");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('sendMessage', {
        'address': address,
        'messageJson': messageJson,
      });
      print("BlueChat [Transport LOG]: sendMessage result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: sendMessage failed: ${e.message}");
      return false;
    }
  }

  Future<bool> broadcastMessage(String messageJson) async {
    print("BlueChat [Transport LOG]: Invoking broadcastMessage with data: $messageJson");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('broadcastMessage', {
        'messageJson': messageJson,
      });
      print("BlueChat [Transport LOG]: broadcastMessage result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: broadcastMessage failed: ${e.message}");
      return false;
    }
  }

  Future<bool> sendFile({
    required String address,
    required String filePath,
    required String fileId,
    required String fileName,
    required int fileSize,
    required String senderName,
  }) async {
    print("BlueChat [Transport LOG]: Invoking sendFile to $address, path: $filePath, name: $fileName, size: $fileSize");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('sendFile', {
        'address': address,
        'filePath': filePath,
        'fileId': fileId,
        'fileName': fileName,
        'fileSize': fileSize,
        'senderName': senderName,
      });
      print("BlueChat [Transport LOG]: sendFile result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: sendFile failed: ${e.message}");
      return false;
    }
  }

  Future<bool> startAudioCall(String address, {bool isVideo = false}) async {
    print("BlueChat [Transport LOG]: Invoking startAudioCall to $address (video: $isVideo)...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('startAudioCall', {
        'address': address,
        'isVideo': isVideo,
      });
      print("BlueChat [Transport LOG]: startAudioCall result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: startAudioCall failed: ${e.message}");
      return false;
    }
  }

  Future<bool> stopAudioCall() async {
    print("BlueChat [Transport LOG]: Invoking stopAudioCall...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('stopAudioCall');
      print("BlueChat [Transport LOG]: stopAudioCall result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: stopAudioCall failed: ${e.message}");
      return false;
    }
  }

  Future<bool> dismissNotification(String sessionId) async {
    print("BlueChat [Transport LOG]: Invoking dismissNotification for session: $sessionId...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('dismissNotification', {'sessionId': sessionId});
      print("BlueChat [Transport LOG]: dismissNotification result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: dismissNotification failed: ${e.message}");
      return false;
    }
  }

  Future<String> getMyAddress() async {
    print("BlueChat [Transport LOG]: Invoking getMyAddress...");
    try {
      final String? result = await _methodChannel.invokeMethod<String>('getMyAddress');
      print("BlueChat [Transport LOG]: getMyAddress result: $result");
      return result ?? '';
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: getMyAddress failed: ${e.message}");
      return '';
    }
  }

  Future<bool> setActiveSessionId(String? sessionId) async {
    print("BlueChat [Transport LOG]: Invoking setActiveSessionId: $sessionId...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('setActiveSessionId', {'sessionId': sessionId});
      print("BlueChat [Transport LOG]: setActiveSessionId result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: setActiveSessionId failed: ${e.message}");
      return false;
    }
  }

  Future<List<Map<String, String>>> getInstalledUpiApps() async {
    print("BlueChat [Transport LOG]: Invoking getInstalledUpiApps...");
    try {
      final List<dynamic>? result = await _methodChannel.invokeMethod<List<dynamic>>('getInstalledUpiApps');
      print("BlueChat [Transport LOG]: getInstalledUpiApps result: $result");
      if (result == null) return [];
      return result.map((item) => Map<String, String>.from(item)).toList();
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: getInstalledUpiApps failed: ${e.message}");
      return [];
    }
  }

  Future<bool> launchUpiPayment(String upiUri, String packageName) async {
    print("BlueChat [Transport LOG]: Invoking launchUpiPayment for app: $packageName...");
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('launchUpiPayment', {
        'upiUri': upiUri,
        'packageName': packageName,
      });
      print("BlueChat [Transport LOG]: launchUpiPayment result: $result");
      return result ?? false;
    } on PlatformException catch (e) {
      print("BlueChat [Transport LOG]: launchUpiPayment failed: ${e.message}");
      return false;
    }
  }
}
