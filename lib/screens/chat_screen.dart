import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/chat_provider.dart';
import '../providers/profile_provider.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/bluetooth_peer.dart';
import '../services/file_transfer_service.dart';
import '../widgets/chat_bubble.dart';


class ChatScreen extends StatefulWidget {
  final String sessionId;
  final String sessionName;

  const ChatScreen({
    Key? key,
    required this.sessionId,
    required this.sessionName,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = "";
  ChatMessage? _replyingToMessage;
  BluetoothPeer? _peer;
  bool _isTypingSent = false;
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = Provider.of<ChatProvider>(context, listen: false);
      provider.setActiveSession(widget.sessionId);
      
      final isGroup = widget.sessionId == "group_chat" || widget.sessionId.startsWith("group_");
      if (!isGroup) {
        final p = await provider.getPeerInfo(widget.sessionId);
        if (mounted) {
          setState(() {
            _peer = p;
          });
        }
      }
    });
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _messageController.addListener(_onMessageTextChanged);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onMessageTextChanged);
    _typingDebounce?.cancel();
    if (_isTypingSent) {
      try {
        final provider = Provider.of<ChatProvider>(context, listen: false);
        final profile = Provider.of<ProfileProvider>(context, listen: false);
        provider.sendTypingStatus(widget.sessionId, false, profile.username);
      } catch (_) {}
    }
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    // Clear active session in provider
    Future.microtask(() {
      try {
        Provider.of<ChatProvider>(context, listen: false).setActiveSession(null);
      } catch (_) {}
    });
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage(ChatProvider chatProvider, ProfileProvider profileProvider) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    _typingDebounce?.cancel();
    if (_isTypingSent) {
      _isTypingSent = false;
      chatProvider.sendTypingStatus(widget.sessionId, false, profileProvider.username);
    }
    final replyMsg = _replyingToMessage;
    setState(() {
      _replyingToMessage = null;
    });

    await chatProvider.sendTextMessage(
      widget.sessionId,
      text,
      profileProvider.username,
      replyToId: replyMsg?.id,
      replyToBody: replyMsg?.body,
      replyToSender: replyMsg?.isSelf == true ? 'Me' : replyMsg?.senderName,
    );
    _scrollToBottom();
  }

  void _pickAndSendFile(String type, ChatProvider chatProvider, ProfileProvider profileProvider) async {
    Navigator.pop(context); // Close bottom sheet
    
    final result = await FileTransferService.pickFile(type);
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final replyMsg = _replyingToMessage;
      setState(() {
        _replyingToMessage = null;
      });
      
      await chatProvider.sendFileMessage(
        sessionId: widget.sessionId,
        filePath: file.path!,
        fileName: file.name,
        fileSize: file.size,
        senderName: profileProvider.username,
        replyToId: replyMsg?.id,
        replyToBody: replyMsg?.body,
        replyToSender: replyMsg?.isSelf == true ? 'Me' : replyMsg?.senderName,
      );
      _scrollToBottom();
    }
  }

  void _showAttachmentMenu(BuildContext context, ChatProvider chatProvider, ProfileProvider profileProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              crossAxisSpacing: 16.0,
              mainAxisSpacing: 16.0,
              children: [
                _buildAttachmentItem(Icons.image, Colors.purple, "Image", () => _pickAndSendFile("image", chatProvider, profileProvider)),
                _buildAttachmentItem(Icons.video_library, Colors.orange, "Video", () => _pickAndSendFile("video", chatProvider, profileProvider)),
                _buildAttachmentItem(Icons.picture_as_pdf, Colors.red, "PDF", () => _pickAndSendFile("pdf", chatProvider, profileProvider)),
                _buildAttachmentItem(Icons.description, Colors.blue, "Doc", () => _pickAndSendFile("doc", chatProvider, profileProvider)),
                _buildAttachmentItem(Icons.audiotrack, Colors.pink, "Audio", () => _pickAndSendFile("audio", chatProvider, profileProvider)),
                _buildAttachmentItem(Icons.android, Colors.green, "APK", () => _pickAndSendFile("apk", chatProvider, profileProvider)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentItem(IconData icon, Color color, String label, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: color.withOpacity(0.15),
          child: IconButton(
            icon: Icon(icon, color: color, size: 28),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 6.0),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _showRenameContactDialog(BuildContext context, ChatProvider chatProvider) {
    final session = chatProvider.chatSessions.firstWhere(
      (s) => s.id == widget.sessionId,
      orElse: () => ChatSession(
        id: widget.sessionId,
        name: widget.sessionName,
        isGroup: false,
        lastMessage: "",
        timestamp: DateTime.now(),
      ),
    );
    final currentName = _peer?.customName ?? session.name;
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Rename Contact", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter contact alias...",
            hintStyle: TextStyle(color: Colors.grey),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await chatProvider.updatePeerCustomName(widget.sessionId, newName);
                final p = await chatProvider.getPeerInfo(widget.sessionId);
                setState(() {
                  _peer = p;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Contact renamed to $newName")),
                );
              }
            },
            child: const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showForwardDialog(BuildContext context, ChatMessage message, ChatProvider chatProvider, ProfileProvider profileProvider) async {
    final sessions = chatProvider.chatSessions.where((s) => s.id != widget.sessionId).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other conversations to forward to'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    const Icon(Icons.forward, color: Colors.orangeAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Forward to...',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final targetSession = sessions[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: targetSession.isGroup ? Colors.green.withOpacity(0.2) : Colors.teal.withOpacity(0.2),
                        child: Icon(
                          targetSession.isGroup ? Icons.group : Icons.person,
                          color: targetSession.isGroup ? Colors.green : Colors.teal,
                        ),
                      ),
                      title: Text(
                        targetSession.name,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        targetSession.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        if (message.type == 'text') {
                          await chatProvider.sendTextMessage(
                            targetSession.id,
                            message.body,
                            profileProvider.username,
                          );
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Forwarded to ${targetSession.name}'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
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

  Widget _buildReplyPreviewBar() {
    if (_replyingToMessage == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: const BoxDecoration(
        color: Colors.black26,
        border: Border(
          top: BorderSide(color: Colors.black12, width: 1.0),
          bottom: BorderSide(color: Colors.black12, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, color: Colors.teal, size: 20),
          const SizedBox(width: 8.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Replying to ${_replyingToMessage!.isSelf ? 'yourself' : _replyingToMessage!.senderName}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
                ),
                const SizedBox(height: 2.0),
                Text(
                  _replyingToMessage!.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              setState(() {
                _replyingToMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isGroup = widget.sessionId == "group_chat" || widget.sessionId.startsWith("group_");
    final isConnected = isGroup 
        ? chatProvider.connectedDevices.isNotEmpty 
        : chatProvider.connectedDevices.any((d) => d.address == widget.sessionId);

    // Find session for wallpaper
    final session = chatProvider.chatSessions.firstWhere(
      (s) => s.id == widget.sessionId,
      orElse: () => ChatSession(
        id: widget.sessionId,
        name: widget.sessionName,
        isGroup: isGroup,
        lastMessage: "",
        timestamp: DateTime.now(),
      ),
    );
    final wallpaperPath = session.wallpaper;

    // List of messages in current session
    var messages = chatProvider.getMessagesForSession(widget.sessionId);

    // Filter messages by search query if search is active
    if (_isSearching && _searchQuery.isNotEmpty) {
      messages = messages.where((msg) {
        return msg.body.toLowerCase().contains(_searchQuery) ||
            (msg.fileName != null && msg.fileName!.toLowerCase().contains(_searchQuery));
      }).toList();
    }

    // Auto-scroll when messages load
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Search message...",
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_peer?.customName ?? session.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (!isGroup)
                    const Text(
                      "🔒 End-to-End Encrypted",
                      style: TextStyle(fontSize: 10, color: Colors.white70),
                    )
                  else
                    const Text(
                      "👥 Local Public Group Broadcast",
                      style: TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                ],
              ),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Color(int.parse(profileProvider.avatarColor, radix: 16)),
        foregroundColor: Colors.white,
        actions: [
          if (!isGroup) ...[
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.greenAccent),
              onPressed: () async {
                final status = await Permission.microphone.request();
                if (status.isGranted) {
                  chatProvider.initiateCall(
                    widget.sessionId,
                    _peer?.customName ?? session.name,
                    profileProvider.username,
                    isVideo: false,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Microphone permission is required for voice calls."),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.videocam, color: Colors.greenAccent),
              onPressed: () async {
                final micStatus = await Permission.microphone.request();
                final cameraStatus = await Permission.camera.request();
                if (micStatus.isGranted && cameraStatus.isGranted) {
                  chatProvider.initiateCall(
                    widget.sessionId,
                    _peer?.customName ?? session.name,
                    profileProvider.username,
                    isVideo: true,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Microphone and Camera permissions are required for video calls."),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
            ),
          ],
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              showMenu(
                context: context,
                position: const RelativeRect.fromLTRB(100, 80, 0, 0),
                items: [
                  PopupMenuItem(
                    child: const Text("Set Wallpaper"),
                    onTap: () {
                      Future.delayed(const Duration(milliseconds: 100), () {
                        _showWallpaperSelectionDialog(context, chatProvider);
                      });
                    },
                  ),
                  if (wallpaperPath != null && wallpaperPath.isNotEmpty)
                    PopupMenuItem(
                      child: const Text("Reset Wallpaper"),
                      onTap: () => chatProvider.setSessionWallpaper(widget.sessionId, null),
                    ),
                  if (!isGroup) ...[
                    PopupMenuItem(
                      child: const Text("Rename Contact"),
                      onTap: () {
                        Future.delayed(const Duration(milliseconds: 100), () {
                          _showRenameContactDialog(context, chatProvider);
                        });
                      },
                    ),
                    PopupMenuItem(
                      child: const Text("Change Contact Photo"),
                      onTap: () {
                        Future.delayed(const Duration(milliseconds: 100), () async {
                          final result = await FilePicker.platform.pickFiles(type: FileType.image);
                          if (result != null && result.files.single.path != null) {
                            await chatProvider.updatePeerProfilePhoto(widget.sessionId, result.files.single.path!);
                            final p = await chatProvider.getPeerInfo(widget.sessionId);
                            setState(() {
                              _peer = p;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Contact photo updated")),
                            );
                          }
                        });
                      },
                    ),
                  ],
                  PopupMenuItem(
                    child: const Text("Clear History"),
                    onTap: () => chatProvider.clearHistory(widget.sessionId),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<BluetoothPeer?>(
        future: isGroup ? Future.value(null) : chatProvider.getPeerInfo(widget.sessionId),
        builder: (context, snapshot) {
          final peer = snapshot.data;
          final connectionStatus = peer?.connectionStatus ?? 'none';

          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0B141A) : const Color(0xFFE5DDD5),
              image: (wallpaperPath != null && wallpaperPath.isNotEmpty && !wallpaperPath.startsWith("gradient:"))
                  ? DecorationImage(
                      image: FileImage(File(wallpaperPath)),
                      fit: BoxFit.cover,
                    )
                  : null,
              gradient: (wallpaperPath != null && wallpaperPath.startsWith("gradient:"))
                  ? _getPresetGradient(wallpaperPath)
                  : null,
            ),
            child: Column(
              children: [
                // Connection Warning Banner
                if (!isGroup && !isConnected && connectionStatus == 'approved')
                  Container(
                    width: double.infinity,
                    color: Colors.blueAccent.withOpacity(0.15),
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.hub, color: Colors.blueAccent, size: 18),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            "Peer offline. Messages will be routed via nearby devices (Mesh Network).",
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                // Messages list
                Expanded(
                  child: messages.isEmpty
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _isSearching ? "No matching messages found." : "No messages. Start the conversation!",
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            return ChatBubble(
                              message: message,
                              onDelete: () => chatProvider.deleteMessage(widget.sessionId, message.id),
                              onReply: (msg) {
                                setState(() {
                                  _replyingToMessage = msg;
                                });
                              },
                              onReact: (reaction) => chatProvider.toggleMessageReaction(
                                widget.sessionId,
                                message.id,
                                reaction,
                                profileProvider.username,
                              ),
                              onForward: (msg) => _showForwardDialog(context, msg, chatProvider, profileProvider),
                            );
                          },
                        ),
                ),

                // Conditional footer depending on WAN connection acceptance status
                if (!isGroup && connectionStatus == 'pending_sent')
                  Container(
                    padding: const EdgeInsets.all(20.0),
                    margin: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
                      ],
                      border: Border.all(color: Colors.teal.withOpacity(0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_clock, size: 40, color: Colors.tealAccent.shade700),
                        const SizedBox(height: 12),
                        const Text(
                          "Connection Request Pending",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Waiting for ${widget.sessionName} to accept your connection request. You can start chatting once they accept! 🌍",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else if (!isGroup && connectionStatus == 'pending_received')
                  Container(
                    padding: const EdgeInsets.all(20.0),
                    margin: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
                      ],
                      border: Border.all(color: Colors.teal.withOpacity(0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.teal.withOpacity(0.15),
                          child: const Icon(Icons.handshake, color: Colors.teal, size: 28),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Connection Request from ${widget.sessionName}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "This user is located 100,000 km away. Connect to enable secure, end-to-end encrypted chat. 🌍",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: const BorderSide(color: Colors.redAccent),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () => chatProvider.declineConnectionRequest(widget.sessionId),
                                child: const Text("Decline", style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () => chatProvider.acceptConnectionRequest(widget.sessionId, widget.sessionName),
                                child: const Text("Accept & Connect", style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else ...[
                  // Reply composing preview bar
                  _buildReplyPreviewBar(),

                  // Message input bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                              borderRadius: BorderRadius.circular(28.0),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.attach_file, color: Colors.blueAccent),
                                  onPressed: () => _showAttachmentMenu(context, chatProvider, profileProvider),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _messageController,
                                    minLines: 1,
                                    maxLines: 5,
                                    keyboardType: TextInputType.multiline,
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                    decoration: const InputDecoration(
                                      hintText: "Message",
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8.0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        GestureDetector(
                          onTap: () => _sendMessage(chatProvider, profileProvider),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: Color(int.parse(profileProvider.avatarColor, radix: 16)),
                            child: const Icon(Icons.send, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _onMessageTextChanged() {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final isTextNotEmpty = _messageController.text.trim().isNotEmpty;
    if (isTextNotEmpty && !_isTypingSent) {
      _isTypingSent = true;
      provider.sendTypingStatus(widget.sessionId, true, profile.username);
    }
    
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      if (_isTypingSent) {
        _isTypingSent = false;
        provider.sendTypingStatus(widget.sessionId, false, profile.username);
      }
    });
  }

  LinearGradient? _getPresetGradient(String gradientToken) {
    switch (gradientToken) {
      case 'gradient:sunset':
        return const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF97316), Color(0xFFEC4899), Color(0xFF8B5CF6)],
        );
      case 'gradient:midnight':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF311042)],
        );
      case 'gradient:ocean':
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F766E), Color(0xFF0F172A)],
        );
      case 'gradient:forest':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF064E3B), Color(0xFF0F172A)],
        );
      case 'gradient:cyberpunk':
        return const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1E1B4B), Color(0xFF00F0FF), Color(0xFFEC4899)],
        );
      default:
        return null;
    }
  }

  void _showWallpaperSelectionDialog(BuildContext context, ChatProvider chatProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(
            "Select Chat Wallpaper",
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: SingleChildScrollView(
             child: Column(
               mainAxisSize: MainAxisSize.min,
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(
                   "Preset Gradients",
                   style: TextStyle(
                     fontWeight: FontWeight.bold,
                     fontSize: 14,
                     color: isDark ? Colors.white70 : Colors.black54,
                   ),
                 ),
                 const SizedBox(height: 12),
                 SizedBox(
                   height: 80,
                   child: ListView(
                     scrollDirection: Axis.horizontal,
                     children: [
                       _buildGradientPreviewItem(context, 'gradient:sunset', 'Sunset', [const Color(0xFFF97316), const Color(0xFFEC4899), const Color(0xFF8B5CF6)], chatProvider),
                       _buildGradientPreviewItem(context, 'gradient:midnight', 'Midnight', [const Color(0xFF0F172A), const Color(0xFF1E1B4B), const Color(0xFF311042)], chatProvider),
                       _buildGradientPreviewItem(context, 'gradient:cyberpunk', 'Cyberpunk', [const Color(0xFF1E1B4B), const Color(0xFF00F0FF), const Color(0xFFEC4899)], chatProvider),
                       _buildGradientPreviewItem(context, 'gradient:ocean', 'Ocean', [const Color(0xFF0F766E), const Color(0xFF0F172A)], chatProvider),
                       _buildGradientPreviewItem(context, 'gradient:forest', 'Forest', [const Color(0xFF064E3B), const Color(0xFF0F172A)], chatProvider),
                     ],
                   ),
                 ),
                 const SizedBox(height: 20),
                 const Divider(),
                 const SizedBox(height: 10),
                 ListTile(
                   contentPadding: EdgeInsets.zero,
                   leading: Icon(Icons.photo_library, color: Color(int.parse(Provider.of<ProfileProvider>(context, listen: false).avatarColor, radix: 16))),
                   title: Text(
                     "Choose Custom Photo",
                     style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                   ),
                   subtitle: Text(
                     "Select an image from your gallery",
                     style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12),
                   ),
                   onTap: () async {
                     Navigator.pop(context);
                     final result = await FilePicker.platform.pickFiles(type: FileType.image);
                     if (result != null && result.files.single.path != null) {
                       await chatProvider.setSessionWallpaper(widget.sessionId, result.files.single.path!);
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text("Wallpaper updated successfully!")),
                       );
                     }
                   },
                 ),
               ],
             ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGradientPreviewItem(
    BuildContext context,
    String token,
    String label,
    List<Color> colors,
    ChatProvider chatProvider,
  ) {
    return GestureDetector(
      onTap: () async {
        Navigator.pop(context);
        await chatProvider.setSessionWallpaper(widget.sessionId, token);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Wallpaper changed to $label")),
        );
      },
      child: Container(
        width: 70,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black45,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
