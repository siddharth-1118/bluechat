import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/profile_provider.dart';
import 'chat_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({Key? key}) : super(key: key);

  @override
  _DevicesScreenState createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _permissionsGranted = false;
  bool _checkingPermissions = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _checkPermissionsAndScan();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionsAndScan() async {
    setState(() {
      _checkingPermissions = true;
    });

    // Request necessary Bluetooth and location permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.notification,
    ].request();

    final locationGranted = statuses[Permission.location]?.isGranted ?? false;
    // On Android 12+, Bluetooth permissions are required. On older versions, location is enough.
    // So we check if Bluetooth permissions are either granted or not restricted (e.g. on older APIs they return permanentlyDenied/denied but we don't need them).
    final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? true;
    final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? true;
    final advertiseGranted = statuses[Permission.bluetoothAdvertise]?.isGranted ?? true;

    final allGranted = locationGranted && scanGranted && connectGranted && advertiseGranted;

    setState(() {
      _permissionsGranted = allGranted;
      _checkingPermissions = false;
    });

    if (allGranted) {
      _pulseController.repeat();
      Provider.of<ChatProvider>(context, listen: false).startScan();
    }
  }

  void _toggleGroupHost(ChatProvider chatProvider) {
    if (chatProvider.isServerRunning) {
      chatProvider.stopServer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bluetooth group host server stopped."),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    } else {
      chatProvider.startServer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bluetooth group host server started! Other devices can now scan and connect."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = Color(int.parse(profileProvider.avatarColor, radix: 16));

    if (_pulseController.isAnimating && !chatProvider.isScanning) {
      _pulseController.stop();
    } else if (!_pulseController.isAnimating && chatProvider.isScanning) {
      _pulseController.repeat();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Devices"),
        backgroundColor: isDark ? const Color(0xFF1E293B) : primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(chatProvider.isScanning ? Icons.stop : Icons.refresh),
            onPressed: _permissionsGranted
                ? () {
                    if (chatProvider.isScanning) {
                      chatProvider.stopScan();
                    } else {
                      chatProvider.startScan();
                    }
                  }
                : null,
          )
        ],
      ),
      body: _checkingPermissions
          ? const Center(child: CircularProgressIndicator())
          : !_permissionsGranted
              ? _buildPermissionWarning(theme)
              : Column(
                  children: [
                    // Group Host Configuration Panel
                    _buildHostPanel(chatProvider, primaryColor, isDark),
                    
                    // Connected/Active Peer Connections List
                    if (chatProvider.connectedDevices.isNotEmpty) ...[
                      _buildSectionHeader(theme, "Active Connections"),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: chatProvider.connectedDevices.length,
                        itemBuilder: (context, index) {
                          final peer = chatProvider.connectedDevices[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: primaryColor,
                              child: const Icon(Icons.link, color: Colors.white),
                            ),
                            title: Text(peer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(peer.address),
                            trailing: TextButton(
                              onPressed: () => chatProvider.disconnectDevice(peer.address),
                              child: const Text("DISCONNECT", style: TextStyle(color: Colors.redAccent)),
                            ),
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(
                                    sessionId: peer.address,
                                    sessionName: peer.name,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],

                    // Scanner Section Header
                    _buildSectionHeader(theme, "Available Devices"),

                    // Scanning Loader Animation
                    if (chatProvider.isScanning)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Container(
                              padding: const EdgeInsets.all(8.0),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: primaryColor.withOpacity(0.2 * (1 - _pulseController.value)),
                              ),
                              child: Icon(Icons.bluetooth_searching, color: primaryColor, size: 36),
                            );
                          },
                        ),
                      ),

                    // Found Devices List
                    Expanded(
                      child: chatProvider.discoveredDevices.isEmpty
                          ? Center(
                              child: Text(
                                chatProvider.isScanning ? "Scanning for nearby devices..." : "No devices found. Tap refresh to scan.",
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: chatProvider.discoveredDevices.length,
                              itemBuilder: (context, index) {
                                final peer = chatProvider.discoveredDevices[index];
                                final isConnecting = peer.connectionState == 'connecting';
                                final isConnected = peer.connectionState == 'connected';

                                return ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.bluetooth),
                                  ),
                                  title: Text(peer.name),
                                  subtitle: Text(peer.address),
                                  trailing: isConnecting
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : isConnected
                                          ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                                          : peer.isBonded
                                              ? const Icon(Icons.star, color: Colors.amber)
                                              : null,
                                  onTap: isConnecting || isConnected
                                      ? null
                                      : () => chatProvider.connectToDevice(peer),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: theme.brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.grey[200],
      child: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildHostPanel(ChatProvider chatProvider, Color primaryColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Local Group Host Server",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    chatProvider.isServerRunning ? "Server Running (Visible to group)" : "Server Offline (Solo mode)",
                    style: TextStyle(
                      color: chatProvider.isServerRunning ? Colors.green : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Switch(
                value: chatProvider.isServerRunning,
                activeColor: primaryColor,
                onChanged: (val) => _toggleGroupHost(chatProvider),
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          Text(
            "Enabling this hosts a local Bluetooth socket group. Once turned on, multiple nearby users can connect to your device to join a shared group chat.",
            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionWarning(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 72, color: Colors.orangeAccent),
            const SizedBox(height: 16),
            Text(
              "Permissions Required",
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "BlueChat requires Bluetooth scanning, connecting, and Location permissions to discover and chat with nearby devices. Please grant these permissions.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _checkPermissionsAndScan,
              child: const Text("Grant Permissions"),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text("Open App Settings"),
            ),
          ],
        ),
      ),
    );
  }
}
