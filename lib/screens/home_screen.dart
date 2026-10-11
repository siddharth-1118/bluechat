import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../database/database_helper.dart';
import '../providers/chat_provider.dart';
import '../providers/profile_provider.dart';
import '../models/bluetooth_peer.dart';
import '../models/chat_message.dart';
import '../services/bluetooth_service.dart';
import '../services/signal_weaver_service.dart';
import '../services/wan_link_service.dart';
import 'devices_screen.dart';
import 'chat_screen.dart';
import 'qr_code_screen.dart';
import 'signal_weaver_screen.dart';
import 'gmail_backup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    // Trigger provider data loads and permission/service setup after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPermissionsAndService();
    });
  }

  Future<void> _initPermissionsAndService() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    // Request all necessary permissions upfront for a smooth first-run experience
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
      Permission.notification,
    ].request();

    final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? true;

    // Now start the foreground service — it's safe since permissions are (potentially) granted
    try {
      await const MethodChannel('com.example.bluechat/methods').invokeMethod('startBluetoothService');
    } catch (e) {
      // Service may already be running — that's fine
    }

    // Initialize chat provider (registers event listeners, loads sessions, etc.)
    chatProvider.init();

    // If permissions were denied, show a warning banner
    if (!connectGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '⚠️ Bluetooth permission denied. Go to Settings → Apps → BlueChat → Permissions to enable Bluetooth.',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Settings',
            textColor: Colors.white,
            onPressed: openAppSettings,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    if (dateTime.day == now.day && dateTime.month == now.month && dateTime.year == now.year) {
      return DateFormat('hh:mm a').format(dateTime);
    } else if (dateTime.day == now.subtract(const Duration(days: 1)).day) {
      return "Yesterday";
    } else {
      return DateFormat('dd/MM/yy').format(dateTime);
    }
  }

  void _showSosBeaconDialog(BuildContext context, ChatProvider chatProvider, ProfileProvider profileProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final detailsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text(
              "Emergency SOS Beacon",
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Instantly broadcast a high-priority distress alert to all nearby Bluetooth mesh nodes and paired contacts without manual pairing.",
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: detailsController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: "Optional details (e.g. Need medical help, GPS/Mile marker)...",
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.redAccent),
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.emergency_share, size: 18),
            label: const Text("Broadcast SOS Now", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(context);
              await chatProvider.broadcastSosAlert(
                profileProvider.username,
                customDetails: detailsController.text.trim(),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("🚨 High-priority Emergency SOS Beacon broadcasted!"),
                  backgroundColor: Colors.redAccent,
                  duration: Duration(seconds: 4),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showStarredMessagesSheet(BuildContext context, ChatProvider chatProvider) async {
    final starred = await chatProvider.getStarredMessages();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      "Starred Messages (${starred.length})",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (starred.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.star_outline, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text("No starred messages yet", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: starred.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final msg = starred[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.amber.withOpacity(0.15),
                          child: const Icon(Icons.star, color: Colors.amber, size: 20),
                        ),
                        title: Text(
                          msg.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        ),
                        subtitle: Text(
                          "${msg.isSelf ? 'You' : msg.senderName} • ${DateFormat('dd MMM hh:mm a').format(msg.timestamp)}",
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.star, color: Colors.amber, size: 20),
                          tooltip: "Unstar",
                          onPressed: () async {
                            await chatProvider.toggleMessageStarred(msg.sessionId, msg.id, false);
                            Navigator.pop(context);
                            _showStarredMessagesSheet(context, chatProvider);
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showPanicWipeDialog(BuildContext context, ChatProvider chatProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: const Row(
          children: [
            Icon(Icons.dangerous, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text(
              "Stealth Panic Wipe",
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          "DANGER: This action instantly and permanently wipes all chat histories, messages, peer records, and Diffie-Hellman encryption keys from this device.\n\nAre you sure you want to proceed?",
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text("PURGE ALL DATA", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(context);
              await chatProvider.performPanicWipe();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("⚠️ Local database and cryptographic keys successfully purged."),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context, ChatProvider chatProvider, ProfileProvider profileProvider) async {
    final peers = await DatabaseHelper.instance.getPeers();
    if (peers.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Create Group', style: TextStyle(color: Colors.white)),
          content: const Text(
            'You do not have any saved contacts. Connect to other devices first to add them to groups.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );
      return;
    }

    final groupNameController = TextEditingController();
    final selectedMembers = <String>{};

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('New Group Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: groupNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Enter group name...',
                        hintStyle: TextStyle(color: Colors.grey),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Select Members:', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: peers.length,
                        itemBuilder: (context, index) {
                          final peer = peers[index];
                          final name = peer.customName ?? peer.name;
                          final address = peer.address;
                          final isSelected = selectedMembers.contains(address);

                          return CheckboxListTile(
                            title: Text(name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(address, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            value: isSelected,
                            activeColor: Colors.teal,
                            checkColor: Colors.white,
                            onChanged: (val) {
                              setModalState(() {
                                if (val == true) {
                                  selectedMembers.add(address);
                                } else {
                                  selectedMembers.remove(address);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () async {
                    final name = groupNameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a group name')),
                      );
                      return;
                    }
                    if (selectedMembers.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please select at least one member')),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    await chatProvider.createGroup(name, selectedMembers.toList(), profileProvider.username);
                  },
                  child: const Text('Create', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = Color(int.parse(profileProvider.avatarColor, radix: 16));

    // Filter sessions
    final sessions = chatProvider.chatSessions.where((s) {
      return s.name.toLowerCase().contains(_searchQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("BlueChat", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bluetooth, size: 12, color: Colors.blueAccent),
                SizedBox(width: 4),
                Text(
                  "Bluetooth Offline Direct",
                  style: TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: isDark ? const Color(0xFF1E293B) : primaryColor,
        foregroundColor: Colors.white,
        actions: [
          StreamBuilder<String>(
            stream: WanLinkService.instance.statusStream,
            initialData: WanLinkService.instance.status,
            builder: (context, snapshot) {
              final status = snapshot.data ?? 'offline';
              final enabled = WanLinkService.instance.isEnabled;
              final icon = status == 'online'
                  ? Icons.cloud_done
                  : status == 'connecting'
                      ? Icons.cloud_sync
                      : Icons.cloud_off;
              final color = !enabled
                  ? Colors.white24
                  : status == 'online'
                      ? Colors.lightGreenAccent
                      : status == 'connecting'
                          ? Colors.amberAccent
                          : Colors.white54;
              final label = !enabled
                  ? "Cloud Relay disabled (tap to enable)"
                  : status == 'online'
                      ? "Cloud Relay online — far-away contacts reachable (tap to disable)"
                      : status == 'connecting'
                          ? "Cloud Relay connecting..."
                          : "Cloud Relay offline — retrying (tap to toggle)";
              return IconButton(
                icon: Icon(icon, color: color, size: 22),
                tooltip: label,
                onPressed: () {
                  WanLinkService.instance.setEnabled(!enabled);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(!enabled
                          ? "Cloud Relay enabled — far-away contacts are reachable."
                          : "Cloud Relay disabled — Bluetooth only."),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: "Search Messages",
            onPressed: () => _showMessageSearchDialog(context, chatProvider),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: "QR Pairing",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const QrCodeScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(chatProvider.isServerRunning ? Icons.wifi_tethering : Icons.wifi_tethering_off),
            tooltip: chatProvider.isServerRunning ? "Group Host Running" : "Host Offline",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DevicesScreen()),
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        child: Column(
          children: [
            // Drawer Header
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : primaryColor,
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white24,
                backgroundImage: profileProvider.profilePhoto.isNotEmpty
                    ? FileImage(File(profileProvider.profilePhoto))
                    : null,
                child: profileProvider.profilePhoto.isEmpty
                    ? Text(
                        profileProvider.username.isNotEmpty ? profileProvider.username[0].toUpperCase() : "U",
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              accountName: Text(
                profileProvider.username,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              accountEmail: Text(
                profileProvider.phoneNumber.isNotEmpty
                    ? "Phone: ${profileProvider.phoneNumber}"
                    : (chatProvider.isServerRunning ? "Hosting Bluetooth Group" : "Offline"),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            // Actions
            ListTile(
              leading: const Icon(Icons.devices, color: Colors.blueAccent),
              title: const Text("Bluetooth Devices"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DevicesScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.badge, color: Colors.indigoAccent),
              title: const Text("My Profile Card"),
              onTap: () {
                Navigator.pop(context);
                _showProfileCardDialog(context, profileProvider, chatProvider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add, color: Colors.teal),
              title: const Text("Create Group Chat"),
              onTap: () {
                Navigator.pop(context);
                _showCreateGroupDialog(context, chatProvider, profileProvider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.backup, color: Colors.amber),
              title: const Text("Gmail Backup Center"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GmailBackupScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.star, color: Colors.amber),
              title: const Text("Starred Messages"),
              onTap: () {
                Navigator.pop(context);
                _showStarredMessagesSheet(context, chatProvider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.emergency_share, color: Colors.redAccent),
              title: const Text("Emergency SOS Beacon"),
              onTap: () {
                Navigator.pop(context);
                _showSosBeaconDialog(context, chatProvider, profileProvider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.deepOrangeAccent),
              title: const Text("Stealth Panic Wipe"),
              onTap: () {
                Navigator.pop(context);
                _showPanicWipeDialog(context, chatProvider);
              },
            ),
            if (chatProvider.connectedDevices.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.link_off, color: Colors.redAccent),
                title: const Text("Disconnect All Connected"),
                onTap: () {
                  chatProvider.disconnectDevice(""); // Triggers full disconnect
                  Navigator.pop(context);
                },
              ),
            const Divider(),
            // Dark Mode Toggle
            SwitchListTile(
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: Colors.amber),
              title: const Text("Dark Theme"),
              value: profileProvider.isDarkMode,
              onChanged: (val) {
                profileProvider.toggleTheme(val);
              },
            ),
            const Spacer(),
            // Version Info
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "BlueChat v1.0.0 (Offline Bluetooth)",
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search chats...",
                prefixIcon: const Icon(Icons.search),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.0),
                ),
              ),
            ),
          ),
          
          // Group Chat Quick Entry
          if (chatProvider.isServerRunning)
            Container(
              margin: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
              padding: const EdgeInsets.all(4.0),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.group, color: Colors.white),
                ),
                title: const Text("Local Broadcast Group", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Tap to open host broadcast chat room"),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text("HOSTING", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChatScreen(
                        sessionId: "group_chat",
                        sessionName: "Local Broadcast Group",
                      ),
                    ),
                  );
                },
              ),
            ),

          // Chat Sessions List
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 72, color: Colors.grey[600]),
                        const SizedBox(height: 16),
                        Text(
                          "No active chats",
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Tap the '+' button to scan and connect",
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    itemCount: sessions.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final session = sessions[index];

                      return FutureBuilder<BluetoothPeer?>(
                        future: session.isGroup ? Future.value(null) : chatProvider.getPeerInfo(session.id),
                        builder: (context, snapshot) {
                          final peer = snapshot.data;
                          final displayName = session.isGroup ? session.name : (peer?.customName ?? session.name);
                          final photoPath = peer?.profilePhoto;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: session.isGroup ? Colors.green : primaryColor.withOpacity(0.2),
                              backgroundImage: (photoPath != null && photoPath.isNotEmpty)
                                  ? FileImage(File(photoPath))
                                  : null,
                              child: (photoPath == null || photoPath.isEmpty)
                                  ? Icon(
                                      session.isGroup ? Icons.group : Icons.person,
                                      color: session.isGroup ? Colors.white : primaryColor,
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: session.unreadCount > 0 ? FontWeight.w800 : FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (session.isMuted) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.volume_off, size: 16, color: isDark ? Colors.white60 : Colors.black45),
                                ],
                                if (session.isPinned) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.push_pin, size: 14, color: Colors.teal),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              session.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: session.unreadCount > 0
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark ? Colors.white60 : Colors.black54),
                                fontWeight: session.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatTimestamp(session.timestamp),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: session.unreadCount > 0 ? Colors.teal : Colors.grey,
                                    fontWeight: session.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                if (session.unreadCount > 0) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.teal,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      session.unreadCount > 99 ? '99+' : session.unreadCount.toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(
                                    sessionId: session.id,
                                    sessionName: displayName,
                                  ),
                                ),
                              );
                            },
                            onLongPress: () {
                              showModalBottomSheet(
                                context: context,
                                builder: (context) => SafeArea(
                                  child: Wrap(
                                    children: [
                                      ListTile(
                                        leading: Icon(session.isPinned ? Icons.pin_drop : Icons.push_pin, color: Colors.teal),
                                        title: Text(session.isPinned ? "Unpin chat" : "Pin chat"),
                                        onTap: () {
                                          Navigator.pop(context);
                                          chatProvider.toggleSessionPin(session.id);
                                        },
                                      ),
                                      ListTile(
                                        leading: Icon(session.isMuted ? Icons.volume_up : Icons.volume_off, color: Colors.blueAccent),
                                        title: Text(session.isMuted ? "Unmute notifications" : "Mute notifications"),
                                        onTap: () {
                                          Navigator.pop(context);
                                          chatProvider.toggleSessionMute(session.id);
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.clear_all, color: Colors.amber),
                                        title: const Text("Clear chat history"),
                                        onTap: () {
                                          Navigator.pop(context);
                                          chatProvider.clearHistory(session.id);
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.delete, color: Colors.redAccent),
                                        title: const Text("Delete conversation"),
                                        onTap: () {
                                          Navigator.pop(context);
                                          DatabaseHelper.instance.deleteSession(session.id);
                                          chatProvider.loadSessionsFromDb();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        }
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const DevicesScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showProfileCardDialog(BuildContext context, ProfileProvider profileProvider, ChatProvider chatProvider) {
    final themeColor = Color(int.parse(profileProvider.avatarColor, radix: 16));
    
    // Gradient matching the selected theme color
    final cardGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        themeColor,
        themeColor.withRed((themeColor.red - 45).clamp(0, 255)).withBlue((themeColor.blue + 45).clamp(0, 255)),
      ],
    );

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: FutureBuilder<String>(
            future: BluetoothService.instance.getMyAddress(),
            builder: (context, snapshot) {
              var macAddress = snapshot.data ?? '';
              if (macAddress.isEmpty) {
                macAddress = SignalWeaverService.instance.myMacAddress;
              }
              final isLoading = snapshot.connectionState == ConnectionState.waiting;
              
              // Prepare QR data payload
              final qrDataMap = {
                "address": macAddress,
                "name": profileProvider.username,
              };
              final qrDataString = jsonEncode(qrDataMap);

              return Card(
                elevation: 16,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: cardGradient,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 46,
                        backgroundColor: Colors.white24,
                        backgroundImage: profileProvider.profilePhoto.isNotEmpty
                            ? FileImage(File(profileProvider.profilePhoto))
                            : null,
                        child: profileProvider.profilePhoto.isEmpty
                            ? Text(
                                profileProvider.username.isNotEmpty ? profileProvider.username[0].toUpperCase() : 'U',
                                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      // Username & Suffix Tag
                      Text(
                        profileProvider.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          "Offline Contact Card",
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // QR Code container
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: isLoading
                            ? const SizedBox(
                                width: 180,
                                height: 180,
                                child: Center(child: CircularProgressIndicator(color: Colors.teal)),
                              )
                            : QrImageView(
                                data: qrDataString,
                                version: QrVersions.auto,
                                size: 180.0,
                                gapless: false,
                                foregroundColor: const Color(0xFF0F172A),
                              ),
                      ),
                      const SizedBox(height: 20),
                      if (macAddress.isNotEmpty) ...[
                        Text(
                          "MAC Address: $macAddress",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),
                      // Close button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.2),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Close",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Timer? _searchDebounce;

  void _showMessageSearchDialog(BuildContext context, ChatProvider chatProvider) {
    final controller = TextEditingController();
    List<ChatMessage> results = [];
    bool loading = false;
    String searched = "";

    String chatNameFor(String sessionId) {
      final idx = chatProvider.chatSessions.indexWhere((s) => s.id == sessionId);
      return idx != -1 ? chatProvider.chatSessions[idx].name : sessionId;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              "Search Messages",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Type to search every chat...",
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      final q = value.trim();
                      if (q.isEmpty) {
                        setModalState(() {
                          results = [];
                          searched = "";
                          loading = false;
                        });
                        return;
                      }
                      setModalState(() {
                        loading = true;
                      });
                      _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
                        final r = await chatProvider.searchMessages(q);
                        setModalState(() {
                          results = r;
                          searched = q;
                          loading = false;
                        });
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                        : results.isEmpty
                            ? Center(
                                child: Text(
                                  searched.isEmpty
                                      ? "Search across every conversation stored on this device."
                                      : "No messages found for \"$searched\".",
                                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.builder(
                                itemCount: results.length,
                                itemBuilder: (listCtx, i) {
                                  final m = results[i];
                                  final chatName = chatNameFor(m.sessionId);
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.tealAccent.withOpacity(0.15),
                                      child: Text(                                        chatName.isNotEmpty ? chatName[0].toUpperCase() : "?",
                                        style: const TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      chatName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    subtitle: Text(
                                      "${m.isSelf ? 'You' : m.senderName}: ${m.body}",
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                    trailing: Text(
                                      DateFormat('dd MMM\nhh:mm a').format(m.timestamp),
                                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                                      textAlign: TextAlign.right,
                                    ),
                                    onTap: () {
                                      Navigator.pop(dialogCtx);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            sessionId: m.sessionId,
                                            sessionName: chatName,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text("Close", style: TextStyle(color: Colors.tealAccent)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showGlobalSearchDialog(BuildContext context, ChatProvider chatProvider, ProfileProvider profileProvider) {
    final searchController = TextEditingController();
    bool isSearching = false;
    String query = "";

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final primaryColor = Color(int.parse(profileProvider.avatarColor, radix: 16));

            Widget buildResultCard(String name, String id) {
              final resultId = "swmp_${id.toLowerCase()}_wan";
              
              return Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                  border: Border.all(
                    color: primaryColor.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: primaryColor.withOpacity(0.15),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : "U",
                            style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "ID: $resultId",
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "100,000 km",
                            style: TextStyle(
                              color: Colors.purpleAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.teal,
                              side: const BorderSide(color: Colors.teal),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.privacy_tip, size: 16),
                            label: const Text(
                              "Simulate Request",
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              await chatProvider.simulateIncomingRequest(
                                peerAddress: resultId,
                                peerName: name,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Simulated incoming request from $name! Check your chat list."),
                                    backgroundColor: Colors.teal,
                                  ),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatScreen(
                                      sessionId: resultId,
                                      sessionName: name,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.connect_without_contact, size: 16),
                            label: const Text(
                              "Connect",
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              await chatProvider.sendConnectionRequest(
                                peerAddress: resultId,
                                peerName: name,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Sent connection request to $name (pending approval)."),
                                    backgroundColor: Colors.teal,
                                  ),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatScreen(
                                      sessionId: resultId,
                                      sessionName: name,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              titlePadding: const EdgeInsets.only(left: 24, right: 24, top: 24),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              title: Row(
                children: [
                  const Icon(Icons.travel_explore, color: Colors.cyanAccent),
                  const SizedBox(width: 8),
                  Text(
                    "Search Global Users",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Search for any username on the global SignalWeaver WAN mesh to initiate a secure connection request.",
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchController,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: "Enter exact username...",
                        hintStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(Icons.search, color: Colors.teal),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.teal),
                                onPressed: () {
                                  searchController.clear();
                                  setModalState(() {
                                    query = "";
                                    isSearching = false;
                                  });
                                },
                              )
                            : null,
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Colors.teal, width: 2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          query = val.trim();
                          if (query.isNotEmpty) {
                            isSearching = true;
                            // Add a tiny mock loading effect for high fidelity
                            Future.delayed(const Duration(milliseconds: 300), () {
                              if (searchController.text.trim() == query) {
                                setModalState(() {
                                  isSearching = false;
                                });
                              }
                            });
                          } else {
                            isSearching = false;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (query.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            Icon(Icons.search, size: 48, color: Colors.teal.withOpacity(0.4)),
                            const SizedBox(height: 8),
                            const Text(
                              "Waiting for input...",
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else if (isSearching)
                      const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(color: Colors.teal),
                      )
                    else
                      buildResultCard(query, query),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
