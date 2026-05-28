import 'dart:convert';

class ChatSession {
  final String id;
  final String name;
  final bool isGroup;
  final String lastMessage;
  final DateTime timestamp;
  final int unreadCount;
  final String? wallpaper;
  final List<String>? members;
  final bool isPinned;
  final bool isMuted;

  ChatSession({
    required this.id,
    required this.name,
    required this.isGroup,
    required this.lastMessage,
    required this.timestamp,
    this.unreadCount = 0,
    this.wallpaper,
    this.members,
    this.isPinned = false,
    this.isMuted = false,
  });

  ChatSession copyWith({
    String? id,
    String? name,
    bool? isGroup,
    String? lastMessage,
    DateTime? timestamp,
    int? unreadCount,
    String? wallpaper,
    List<String>? members,
    bool? isPinned,
    bool? isMuted,
  }) {
    return ChatSession(
      id: id ?? this.id,
      name: name ?? this.name,
      isGroup: isGroup ?? this.isGroup,
      lastMessage: lastMessage ?? this.lastMessage,
      timestamp: timestamp ?? this.timestamp,
      unreadCount: unreadCount ?? this.unreadCount,
      wallpaper: wallpaper ?? this.wallpaper,
      members: members ?? this.members,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'is_group': isGroup ? 1 : 0,
      'last_message': lastMessage,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'wallpaper': wallpaper,
      'members': members != null ? jsonEncode(members) : null,
      'is_pinned': isPinned ? 1 : 0,
      'is_muted': isMuted ? 1 : 0,
    };
  }

  factory ChatSession.fromMap(Map<String, dynamic> map, {int unreadCount = 0}) {
    List<String>? parsedMembers;
    if (map['members'] != null) {
      try {
        parsedMembers = List<String>.from(jsonDecode(map['members']));
      } catch (_) {}
    }
    return ChatSession(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      isGroup: map['is_group'] == 1,
      lastMessage: map['last_message'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
      unreadCount: unreadCount,
      wallpaper: map['wallpaper'],
      members: parsedMembers,
      isPinned: map['is_pinned'] == 1,
      isMuted: map['is_muted'] == 1,
    );
  }
}
