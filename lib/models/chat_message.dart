class ChatMessage {
  final String id;
  final String sessionId;
  final String senderName;
  final String senderAddress;
  final String body;
  final String type; // 'text', 'file', 'call_summary', etc.
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final DateTime timestamp;
  final String status; // 'sending', 'sent', 'delivered', 'failed'
  final bool isSelf;
  
  // Reply properties
  final String? replyToId;
  final String? replyToBody;
  final String? replyToSender;
  
  // Reaction properties
  final String? reaction;

  // Runtime values not persisted in database
  double fileTransferProgress; // 0.0 to 1.0
  double fileTransferSpeed; // bytes per second
  String fileTransferStatus; // 'idle', 'transferring', 'success', 'failed'
  String? error;

  ChatMessage({
    required this.id,
    required this.sessionId,
    required this.senderName,
    required this.senderAddress,
    required this.body,
    required this.type,
    this.filePath,
    this.fileName,
    this.fileSize,
    required this.timestamp,
    required this.status,
    required this.isSelf,
    this.replyToId,
    this.replyToBody,
    this.replyToSender,
    this.reaction,
    this.fileTransferProgress = 0.0,
    this.fileTransferSpeed = 0.0,
    this.fileTransferStatus = 'idle',
    this.error,
  });

  ChatMessage copyWith({
    String? id,
    String? sessionId,
    String? senderName,
    String? senderAddress,
    String? body,
    String? type,
    String? filePath,
    String? fileName,
    int? fileSize,
    DateTime? timestamp,
    String? status,
    bool? isSelf,
    String? replyToId,
    String? replyToBody,
    String? replyToSender,
    String? reaction,
    double? fileTransferProgress,
    double? fileTransferSpeed,
    String? fileTransferStatus,
    String? error,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      senderName: senderName ?? this.senderName,
      senderAddress: senderAddress ?? this.senderAddress,
      body: body ?? this.body,
      type: type ?? this.type,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      isSelf: isSelf ?? this.isSelf,
      replyToId: replyToId ?? this.replyToId,
      replyToBody: replyToBody ?? this.replyToBody,
      replyToSender: replyToSender ?? this.replyToSender,
      reaction: reaction ?? this.reaction,
      fileTransferProgress: fileTransferProgress ?? this.fileTransferProgress,
      fileTransferSpeed: fileTransferSpeed ?? this.fileTransferSpeed,
      fileTransferStatus: fileTransferStatus ?? this.fileTransferStatus,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'sender_name': senderName,
      'sender_address': senderAddress,
      'body': body,
      'type': type,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': status,
      'is_self': isSelf ? 1 : 0,
      'reply_to_id': replyToId,
      'reply_to_body': replyToBody,
      'reply_to_sender': replyToSender,
      'reaction': reaction,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final rId = map['reply_to_id'];
    final rBody = map['reply_to_body'];
    final rSender = map['reply_to_sender'];
    return ChatMessage(
      id: map['id'] ?? '',
      sessionId: map['session_id'] ?? '',
      senderName: map['sender_name'] ?? '',
      senderAddress: map['sender_address'] ?? '',
      body: map['body'] ?? '',
      type: map['type'] ?? 'text',
      filePath: map['file_path'],
      fileName: map['file_name'],
      fileSize: map['file_size'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
      status: map['status'] ?? 'sent',
      isSelf: map['is_self'] == 1,
      replyToId: (rId == null || rId == 'null') ? null : rId,
      replyToBody: (rBody == null || rBody == 'null') ? null : rBody,
      replyToSender: (rSender == null || rSender == 'null') ? null : rSender,
      reaction: map['reaction'] == 'null' ? null : map['reaction'],
      fileTransferStatus: map['type'] == 'file' ? 'success' : 'idle',
      fileTransferProgress: map['type'] == 'file' ? 1.0 : 0.0,
    );
  }
}
