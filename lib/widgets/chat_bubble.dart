import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import 'file_transfer_widget.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onDelete;
  final Function(ChatMessage)? onReply;
  final Function(String?)? onReact;
  final Function(ChatMessage)? onForward;
  final VoidCallback? onToggleStar;

  const ChatBubble({
    Key? key,
    required this.message,
    required this.onDelete,
    this.onReply,
    this.onReact,
    this.onForward,
    this.onToggleStar,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final bgSelf = message.type == 'sos_alert'
        ? Colors.red.shade900
        : (isDark ? const Color(0xFF0F5A47) : const Color(0xFFDCF8C6));
    final bgOther = message.type == 'sos_alert'
        ? Colors.red.shade800
        : (isDark ? const Color(0xFF252D32) : Colors.white);
    final textSelf = isDark ? Colors.white : (message.type == 'sos_alert' ? Colors.white : Colors.black87);
    final textOther = isDark ? Colors.white : (message.type == 'sos_alert' ? Colors.white : Colors.black87);

    final align = message.isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final margin = message.isSelf 
        ? const EdgeInsets.only(left: 64.0, right: 8.0, top: 6.0, bottom: 8.0) 
        : const EdgeInsets.only(left: 8.0, right: 64.0, top: 6.0, bottom: 8.0);

    final timeFormat = DateFormat('hh:mm a');
    final timeStr = timeFormat.format(message.timestamp);

    Widget statusIcon() {
      if (!message.isSelf) return const SizedBox.shrink();
      switch (message.status) {
        case 'sending':
          return const Icon(Icons.schedule, size: 14, color: Colors.white54);
        case 'pending_key_exchange':
          return const Icon(Icons.vpn_key, size: 14, color: Colors.amberAccent);
        case 'sent':
          return const Icon(Icons.check, size: 14, color: Colors.white54);
        case 'delivered':
          return const Icon(Icons.done_all, size: 14, color: Colors.white70);
        case 'read':
          return const Icon(Icons.done_all, size: 14, color: Colors.lightBlueAccent); // True Blue Ticks
        case 'failed':
          return const Icon(Icons.error_outline, size: 14, color: Colors.redAccent);
        default:
          return const SizedBox.shrink();
      }
    }

    Widget buildReplyPreview() {
      if (message.replyToId == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(bottom: 6.0),
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8.0),
          border: Border(
            left: BorderSide(
              color: message.isSelf ? Colors.white70 : Colors.teal,
              width: 4.0,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.replyToSender ?? 'Peer',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: message.isSelf ? Colors.white70 : Colors.teal,
              ),
            ),
            const SizedBox(height: 2.0),
            Text(
              message.replyToBody ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: message.isSelf ? Colors.white60 : (isDark ? Colors.white70 : Colors.black54),
              ),
            ),
          ],
        ),
      );
    }

    Widget bubbleBody = Container(
      decoration: BoxDecoration(
        color: message.isSelf ? bgSelf : bgOther,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16.0),
          topRight: const Radius.circular(16.0),
          bottomLeft: message.isSelf ? const Radius.circular(16.0) : Radius.zero,
          bottomRight: message.isSelf ? Radius.zero : const Radius.circular(16.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!message.isSelf && (message.sessionId == "group_chat" || message.sessionId.startsWith("group_"))) ...[
              Text(
                message.senderName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4.0),
            ],
            buildReplyPreview(),
            if (message.type == 'file')
              SizedBox(
                width: 250,
                child: FileTransferWidget(message: message),
              )
            else if (message.type == 'call_missed' || message.type == 'call_outgoing_missed' || message.type == 'call_summary')
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    message.type == 'call_missed'
                        ? Icons.call_missed
                        : message.type == 'call_outgoing_missed'
                            ? Icons.call_missed_outgoing
                            : Icons.call,
                    color: message.type == 'call_missed' ? Colors.redAccent : Colors.greenAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    message.body,
                    style: TextStyle(
                      color: message.isSelf ? textSelf : textOther,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            else if (message.type == 'system')
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message.body,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              )
            else if (message.type == 'encrypted_pending' || (message.body.trim().startsWith('{"iv":') && message.body.contains('"ct":')))
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_clock, size: 16, color: Colors.amberAccent),
                  const SizedBox(width: 6.0),
                  Text(
                    "Encrypted Message (Handshake Pending)",
                    style: TextStyle(
                      color: message.isSelf ? textSelf : textOther,
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                    ),
                  ),
                ],
              )
            else
              Text(
                message.body,
                style: TextStyle(
                  color: message.isSelf ? textSelf : textOther,
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 4.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.isStarred) ...[
                  const Icon(Icons.star, size: 12, color: Colors.amber),
                  const SizedBox(width: 3.0),
                ],
                Text(
                  timeStr,
                  style: TextStyle(
                    color: message.isSelf ? Colors.white60 : (isDark ? Colors.white54 : Colors.black54),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 4.0),
                statusIcon(),
              ],
            ),
          ],
        ),
      ),
    );

    // Apply Reaction Badge if present
    if (message.reaction != null && message.reaction!.isNotEmpty) {
      bubbleBody = Stack(
        clipBehavior: Clip.none,
        children: [
          bubbleBody,
          Positioned(
            bottom: -8,
            right: message.isSelf ? null : 12,
            left: message.isSelf ? 12 : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                  width: 1,
                ),
              ),
              child: Text(
                message.reaction!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onDoubleTap: () {
        if (onReact != null) {
          final newReaction = message.reaction == '❤️' ? null : '❤️';
          onReact!(newReaction);
        }
      },
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) {
            return SafeArea(
              child: Wrap(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['❤️', '👍', '😂', '😮', '😢', '🙏'].map((emoji) {
                        final isSelected = message.reaction == emoji;
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            if (onReact != null) {
                              onReact!(isSelected ? null : emoji);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? Colors.teal.withOpacity(0.2) 
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 26),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const Divider(height: 1),
                  if (message.type == 'text')
                    ListTile(
                      leading: const Icon(Icons.copy, color: Colors.blueAccent),
                      title: Text('Copy Text', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                      onTap: () {
                        Navigator.pop(context);
                        Clipboard.setData(ClipboardData(text: message.body));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Message copied to clipboard'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  if (onReply != null && message.type != 'system')
                    ListTile(
                      leading: const Icon(Icons.reply, color: Colors.teal),
                      title: Text('Reply', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                      onTap: () {
                        Navigator.pop(context);
                        onReply!(message);
                      },
                    ),
                  if (onToggleStar != null)
                    ListTile(
                      leading: Icon(message.isStarred ? Icons.star_border : Icons.star, color: Colors.amber),
                      title: Text(message.isStarred ? 'Unstar Message' : 'Star Message', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                      onTap: () {
                        Navigator.pop(context);
                        onToggleStar!();
                      },
                    ),
                  if (onForward != null && (message.type == 'text' || message.type == 'file'))
                    ListTile(
                      leading: const Icon(Icons.forward, color: Colors.orangeAccent),
                      title: Text('Forward', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                      onTap: () {
                        Navigator.pop(context);
                        onForward!(message);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.redAccent),
                    title: Text('Delete Message', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                    onTap: () {
                      Navigator.pop(context);
                      onDelete();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
      child: Container(
        margin: margin,
        child: Column(
          crossAxisAlignment: align,
          children: [
            bubbleBody,
          ],
        ),
      ),
    );
  }
}
