import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/chat_provider.dart';
import '../providers/profile_provider.dart';
import '../services/bluetooth_service.dart';
import '../services/signal_weaver_service.dart';
import '../models/bluetooth_peer.dart';
import 'chat_screen.dart';

class QrCodeScreen extends StatefulWidget {
  const QrCodeScreen({Key? key}) : super(key: key);

  @override
  State<QrCodeScreen> createState() => _QrCodeScreenState();
}

class _QrCodeScreenState extends State<QrCodeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _myMacAddress = '';
  bool _isLoadingAddress = true;
  bool _hasCameraPermission = false;
  bool _checkingPermission = true;
  bool _isConnecting = false;
  
  late final MobileScannerController _scannerController;
  int _currentTabIndex = 0;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
      autoStart: false,
    );
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadMacAddress();
    _checkCameraPermission();
  }

  void _handleTabChange() {
    if (_currentTabIndex != _tabController.index) {
      setState(() {
        _currentTabIndex = _tabController.index;
      });
      if (_tabController.index == 1) {
        // Switched to Scanner tab
        if (!_hasCameraPermission) {
          _requestCameraPermission();
        } else {
          _startScanner();
        }
      } else {
        // Switched away from Scanner tab
        _stopScanner();
      }
    }
  }

  void _startScanner() {
    try {
      _scannerController.start();
    } catch (e) {
      print("QrCodeScreen: Error starting scanner: $e");
    }
  }

  void _stopScanner() {
    try {
      _scannerController.stop();
    } catch (e) {
      print("QrCodeScreen: Error stopping scanner: $e");
    }
  }

  Future<void> _loadMacAddress() async {
    var addr = await BluetoothService.instance.getMyAddress();
    if (addr.isEmpty) {
      addr = SignalWeaverService.instance.myMacAddress;
    }
    if (mounted) {
      setState(() {
        _myMacAddress = addr;
        _isLoadingAddress = false;
      });
    }
  }

  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.status;
    if (mounted) {
      setState(() {
        _hasCameraPermission = status.isGranted;
        _checkingPermission = false;
      });
      if (status.isGranted && _tabController.index == 1) {
        _startScanner();
      }
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _hasCameraPermission = status.isGranted;
      });
      if (status.isGranted && _tabController.index == 1) {
        _startScanner();
      }
    }
  }

  Future<void> _pickQrImageFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final capture = await _scannerController.analyzeImage(path);
        if (capture != null && capture.barcodes.isNotEmpty) {
          _onDetect(capture);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("No QR code detected in the selected image."),
                backgroundColor: Colors.orangeAccent,
              ),
            );
          }
        }
      }
    } catch (e) {
      print("QrCodeScreen: Error scanning image from gallery: $e");
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isConnecting) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final data = barcode.rawValue!;
        try {
          final Map<String, dynamic> peerData = jsonDecode(data);
          final address = peerData["address"] as String?;
          final name = peerData["name"] as String? ?? "Unknown Peer";

          if (address != null && address.isNotEmpty) {
            setState(() {
              _isConnecting = true;
            });

            // Stop camera immediately to prevent multiple scans and release resource
            _stopScanner();

            // Vibrate to confirm scan
            try {
              Feedback.forLongPress(context);
            } catch (_) {}

            // Show prompt to choose Local Bluetooth or Remote WAN
            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogCtx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      Icon(Icons.hub, color: Colors.teal.shade400, size: 24),
                      const SizedBox(width: 8),
                      const Text("Peer Detected", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  content: Text(
                    "Do you want to pair with $name ($address) locally via Bluetooth or add them as a Remote WAN contact for long-distance chatting?",
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        setState(() {
                          _isConnecting = false;
                        });
                        // Resume camera scanning since pairing was cancelled
                        _startScanner();
                      },
                      child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        _connectLocalBluetooth(address, name);
                      },
                      child: const Text("Local Bluetooth", style: TextStyle(color: Colors.white)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        _addRemoteWanContact(address, name);
                      },
                      child: const Text("Remote WAN", style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            }
            break;
          }
        } catch (e) {
          print("QrCodeScreen: Error parsing QR Code data: $e");
        }
      }
    }
  }

  void _connectLocalBluetooth(String address, String name) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final peer = BluetoothPeer(
      name: name,
      address: address,
      isBonded: false,
      connectionState: 'connecting',
    );

    await chatProvider.connectToDevice(peer);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connecting to $name via Bluetooth...'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            sessionId: address,
            sessionName: name,
          ),
        ),
      );
    }
  }

  void _addRemoteWanContact(String address, String name) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    await chatProvider.addRemoteContact(name, address);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $name as Remote WAN Contact!'),
          backgroundColor: Colors.teal,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            sessionId: address,
            sessionName: name,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = Color(int.parse(profile.avatarColor, radix: 16));

    // Prepare QR data
    final qrDataMap = {
      "address": _myMacAddress,
      "name": profile.username.isNotEmpty ? profile.username : "BlueChat User",
    };
    final qrDataString = jsonEncode(qrDataMap);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium Dark Slate
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Pair via QR Code',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: themeColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: themeColor,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_2), text: 'My Code'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan Code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Show QR Code
          _buildMyCodeTab(profile, qrDataString, themeColor),

          // Tab 2: Scan QR Code
          _buildScanTab(themeColor),
        ],
      ),
    );
  }

  Widget _buildMyCodeTab(ProfileProvider profile, String qrData, Color themeColor) {
    if (_isLoadingAddress) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.teal),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          children: [
            const Text(
              'Show this code to your partner to let them connect to you instantly.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: themeColor.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24.0),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 260.0,
                gapless: false,
                foregroundColor: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 32),
            // Profile details card
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: themeColor.withOpacity(0.2),
                    backgroundImage: profile.profilePhoto.isNotEmpty
                        ? FileImage(File(profile.profilePhoto))
                        : null,
                    child: profile.profilePhoto.isEmpty
                        ? Text(
                            profile.username.isNotEmpty ? profile.username[0].toUpperCase() : 'U',
                            style: TextStyle(color: themeColor, fontSize: 22, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.username.isNotEmpty ? profile.username : 'BlueChat User',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'MAC: $_myMacAddress',
                          style: const TextStyle(color: Colors.grey, fontSize: 13, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanTab(Color themeColor) {
    if (_checkingPermission) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.teal),
      );
    }

    if (!_hasCameraPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Camera Permission Required',
                style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'We need access to your camera to scan peer connection QR codes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: _requestCameraPermission,
                child: const Text('Grant Permission', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    // Lazy load / build scanner only when the Scanner Tab (index 1) is active.
    // This stops the camera resource from starting prematurely and releases it when switching tabs.
    if (_currentTabIndex != 1) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.teal),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_outlined, size: 56, color: Colors.orangeAccent),
                    const SizedBox(height: 16),
                    Text(
                      'Camera unavailable: ${error.errorCode.name}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You can retry restarting the camera, or pick a QR code image from your gallery.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: themeColor),
                      onPressed: () => _startScanner(),
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text('Retry Camera', style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.teal)),
                      onPressed: _pickQrImageFromGallery,
                      icon: const Icon(Icons.photo_library, color: Colors.teal),
                      label: const Text('Pick Image from Gallery', style: TextStyle(color: Colors.teal)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Overlay scanner UI
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: themeColor, width: 4),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        // Top Toolbar (Flashlight, Camera Switch, Pick Gallery)
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: IconButton(
                  icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off, color: _isTorchOn ? Colors.amberAccent : Colors.white),
                  tooltip: "Toggle Flashlight",
                  onPressed: () async {
                    try {
                      await _scannerController?.toggleTorch();
                      setState(() {
                        _isTorchOn = !_isTorchOn;
                      });
                    } catch (_) {}
                  },
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: IconButton(
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                  tooltip: "Switch Camera",
                  onPressed: () async {
                    try {
                      await _scannerController?.switchCamera();
                    } catch (_) {}
                  },
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: IconButton(
                  icon: const Icon(Icons.photo_library, color: Colors.white),
                  tooltip: "Scan Image from Gallery",
                  onPressed: _pickQrImageFromGallery,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Align the QR code within the frame to scan',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
        if (_isConnecting)
          Container(
            color: Colors.black.withOpacity(0.75),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.teal),
                  SizedBox(height: 16),
                  Text(
                    'Connecting to peer...',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
