import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/profile_provider.dart';

class CallOverlay extends StatefulWidget {
  const CallOverlay({Key? key}) : super(key: key);

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final callState = chatProvider.callState;

    if (callState == 'idle') {
      return const SizedBox.shrink();
    }

    final String peerName = chatProvider.activeCallPeerName ?? 'Peer';
    final String initial = peerName.isNotEmpty ? peerName[0].toUpperCase() : 'P';
    final accentColor = Color(int.parse(profileProvider.avatarColor, radix: 16));
    final isVideo = chatProvider.isVideoCall;

    return Material(
      color: Colors.black.withOpacity(0.95),
      child: SafeArea(
        child: Stack(
          children: [
            // Background / Remote Video (if video call and active)
            if (isVideo && callState == 'active')
              Positioned.fill(
                child: ValueListenableBuilder<dynamic>(
                  valueListenable: chatProvider.remoteVideoFrame,
                  builder: (context, frame, child) {
                    if (frame == null) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.greenAccent),
                            SizedBox(height: 16),
                            Text(
                              "Waiting for remote video...",
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }
                    return Image.memory(
                      frame,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    );
                  },
                ),
              ),

            // Main Column for overlay contents (header + controls)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Header Status
                    Column(
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          callState == 'calling'
                              ? (isVideo ? 'CALLING (VIDEO)...' : 'CALLING...')
                              : callState == 'incoming'
                                  ? (isVideo ? 'INCOMING VIDEO CALL' : 'INCOMING VOICE CALL')
                                  : (isVideo ? 'ACTIVE VIDEO CALL' : 'ACTIVE VOICE CALL'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4.0, offset: Offset(1, 1))
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          peerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4.0, offset: Offset(1, 1))
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (callState == 'active')
                          Text(
                            _formatDuration(chatProvider.callDuration),
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 4.0, offset: Offset(1, 1))
                              ],
                            ),
                          )
                        else
                          Text(
                            isVideo ? 'BlueChat Secure P2P Video' : 'BlueChat Secure P2P Audio',
                            style: const TextStyle(
                              color: Colors.white30,
                              fontSize: 14,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 4.0, offset: Offset(1, 1))
                              ],
                            ),
                          ),
                      ],
                    ),

                    // Central element: Pulsing avatar (only for audio calls or non-active video calls)
                    if (!isVideo || callState != 'active')
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 160 + (40 * _pulseController.value),
                                height: 160 + (40 * _pulseController.value),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (callState == 'active' ? Colors.greenAccent : accentColor)
                                      .withOpacity(0.2 * (1 - _pulseController.value)),
                                ),
                              );
                            },
                          ),
                          CircleAvatar(
                            radius: 70,
                            backgroundColor: callState == 'active' ? Colors.green : accentColor,
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 54,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      const SizedBox.shrink(), // Space filled by background video

                    // Control Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (callState == 'incoming') ...[
                          // Decline Button
                          GestureDetector(
                            onTap: () => chatProvider.declineCall(),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16.0),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.redAccent,
                                  ),
                                  child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Decline',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    shadows: [
                                      Shadow(color: Colors.black54, blurRadius: 4.0, offset: Offset(1, 1))
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 80),
                          // Accept Button
                          GestureDetector(
                            onTap: () => chatProvider.acceptCall(),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16.0),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.greenAccent,
                                  ),
                                  child: Icon(
                                    isVideo ? Icons.videocam : Icons.call,
                                    color: Colors.black,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Accept',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    shadows: [
                                      Shadow(color: Colors.black54, blurRadius: 4.0, offset: Offset(1, 1))
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Hangup Button for calling or active calls
                          GestureDetector(
                            onTap: () => chatProvider.hangUp(),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16.0),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.redAccent,
                                  ),
                                  child: const Icon(Icons.call_end, color: Colors.white, size: 36),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'End Call',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    shadows: [
                                      Shadow(color: Colors.black54, blurRadius: 4.0, offset: Offset(1, 1))
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // PiP / Local Video Preview (only for video calls and active state)
            if (isVideo && callState == 'active')
              Positioned(
                top: 24,
                right: 24,
                width: 100,
                height: 150,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white30, width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 6.0, offset: Offset(2, 2))
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ValueListenableBuilder<dynamic>(
                    valueListenable: chatProvider.localVideoFrame,
                    builder: (context, frame, child) {
                      if (frame == null) {
                        return Container(
                          color: Colors.black87,
                          child: const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                            ),
                          ),
                        );
                      }
                      return Image.memory(
                        frame,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
