import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/signal_weaver_service.dart';
import '../providers/profile_provider.dart';

class SignalWeaverScreen extends StatefulWidget {
  const SignalWeaverScreen({Key? key}) : super(key: key);

  @override
  _SignalWeaverScreenState createState() => _SignalWeaverScreenState();
}

class _SignalWeaverScreenState extends State<SignalWeaverScreen> {
  final _distanceController = TextEditingController(text: "100000");
  bool _isSimulated = false;
  double _distanceKm = 100000;

  @override
  void initState() {
    super.initState();
    _isSimulated = SignalWeaverService.instance.isWanSimulated;
    _distanceKm = SignalWeaverService.instance.simulatedDistance;
    if (_distanceKm == 0) {
      _distanceKm = 100000;
    }
    _distanceController.text = _distanceKm.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _distanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = Provider.of<ProfileProvider>(context);
    final isDark = profileProvider.isDarkMode;
    final primaryColor = Color(int.parse(profileProvider.avatarColor, radix: 16));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("SignalWeaver Matrix", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.black.withOpacity(0.2)),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark 
                ? [const Color(0xFF0F172A), const Color(0xFF1E1E38), const Color(0xFF0F0F1A)]
                : [Colors.blue.shade50, Colors.purple.shade50, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<Map<String, dynamic>>(
            stream: SignalWeaverService.instance.statusStream,
            initialData: {
              "isUdpScanning": SignalWeaverService.instance.isUdpScanning,
              "isTcpServerRunning": SignalWeaverService.instance.isTcpServerRunning,
              "isInternetAvailable": SignalWeaverService.instance.isInternetAvailable,
              "isWanSimulated": SignalWeaverService.instance.isWanSimulated,
              "simulatedDistance": SignalWeaverService.instance.simulatedDistance,
              "connectedIpsCount": SignalWeaverService.instance.connectedIps.length,
              "localIp": SignalWeaverService.instance.myIp,
              "localMac": SignalWeaverService.instance.myMacAddress,
            },
            builder: (context, snapshot) {
              final status = snapshot.data ?? {};
              final localIp = status["localIp"] as String? ?? "Unknown";
              final localMac = status["localMac"] as String? ?? "Unknown";
              final connectedIpsCount = status["connectedIpsCount"] as int? ?? 0;
              final isUdp = status["isUdpScanning"] as bool? ?? false;
              final isTcp = status["isTcpServerRunning"] as bool? ?? false;
              final isWan = status["isInternetAvailable"] as bool? ?? false;

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                children: [
                  // --- Active Bindings Grid ---
                  _buildSectionTitle("Active Connectivity Bindings", isDark),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    children: [
                      _buildTransportCard(
                        title: "Bluetooth",
                        subtitle: "Classic RFCOMM",
                        icon: Icons.bluetooth,
                        color: Colors.blueAccent,
                        isActive: true,
                        extra: localMac.length > 10 ? localMac.substring(0, 10) : localMac,
                        isDark: isDark,
                      ),
                      _buildTransportCard(
                        title: "Wi-Fi LAN",
                        subtitle: connectedIpsCount > 0 ? "$connectedIpsCount Peers" : (isTcp ? "Listening" : "Offline"),
                        icon: Icons.wifi,
                        color: Colors.green,
                        isActive: isUdp || isTcp || connectedIpsCount > 0,
                        extra: localIp,
                        isDark: isDark,
                      ),
                      _buildTransportCard(
                        title: "WAN Gateway",
                        subtitle: isWan ? "Relay Connected" : "Local Only",
                        icon: Icons.cloud,
                        color: Colors.purpleAccent,
                        isActive: isWan,
                        extra: isWan ? "Internet Online" : "No Internet Link",
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // --- WAN Simulation Panel ---
                  _buildSectionTitle("WAN Distance Relaying Bridge", isDark),
                  const SizedBox(height: 8),
                  _buildGlassmorphicContainer(
                    isDark: isDark,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Simulate Distance Routing",
                                    style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Binds offline signals with network WAN pathways",
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                  ),
                                ],
                              ),
                              Switch(
                                value: _isSimulated,
                                activeColor: primaryColor,
                                onChanged: (val) {
                                  setState(() {
                                    _isSimulated = val;
                                  });
                                  SignalWeaverService.instance.toggleWanSimulation(val, _distanceKm);
                                },
                              ),
                            ],
                          ),
                          if (_isSimulated) ...[
                            const Divider(height: 24),
                            Text(
                              "Simulated Distance (km): ${_distanceKm.toStringAsFixed(0)} km",
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Slider(
                              value: _distanceKm,
                              min: 100,
                              max: 100000,
                              divisions: 99,
                              activeColor: primaryColor,
                              inactiveColor: isDark ? Colors.white12 : Colors.black12,
                              onChanged: (val) {
                                setState(() {
                                  _distanceKm = val;
                                });
                                SignalWeaverService.instance.toggleWanSimulation(true, val);
                              },
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.withOpacity(0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.hub_outlined, color: Colors.blueAccent, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Active Path: Me ➜ Local Wi-Fi Router ➜ WAN Gateway ➜ Remote Broker ➜ Target Recipient (Simulated)",
                                      style: TextStyle(
                                        color: isDark ? Colors.blue.shade200 : Colors.blue.shade900,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- Live Routing logs ---
                  _buildSectionTitle("Live Multi-Transport Packet Logs", isDark),
                  const SizedBox(height: 8),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: SignalWeaverService.instance.logsStream,
                    initialData: SignalWeaverService.instance.currentLogs,
                    builder: (context, logSnapshot) {
                      final logs = logSnapshot.data ?? [];
                      if (logs.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          alignment: Alignment.center,
                          child: Text(
                            "No packets routed yet. Start chatting to trigger signals!",
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          final direction = log["direction"] as String;
                          final transport = log["transport"] as String;
                          final status = log["status"] as String;
                          final timestamp = log["timestamp"] as int;
                          final timeStr = TimeOfDay.fromDateTime(
                            DateTime.fromMillisecondsSinceEpoch(timestamp),
                          ).format(context);

                          if (direction == "system") {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.withOpacity(0.12)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("⚙️", style: TextStyle(fontSize: 11)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        status,
                                        style: const TextStyle(color: Colors.grey, fontSize: 10.5, fontFamily: 'monospace'),
                                      ),
                                    ),
                                    Text(timeStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 9)),
                                  ],
                                ),
                              ),
                            );
                          }

                          final isIncoming = direction == "incoming";
                          final hops = log["hops"] as int? ?? 0;
                          final distance = log["distance"] as double? ?? 0.0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: isDark ? const Color(0xFF1E293B).withOpacity(0.6) : Colors.white,
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isIncoming 
                                    ? Colors.green.withOpacity(0.15) 
                                    : Colors.blue.withOpacity(0.15),
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: isIncoming 
                                    ? Colors.green.withOpacity(0.15) 
                                    : Colors.blue.withOpacity(0.15),
                                child: Icon(
                                  isIncoming ? Icons.download_rounded : Icons.upload_rounded,
                                  color: isIncoming ? Colors.green : Colors.blue,
                                  size: 16,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    isIncoming ? "PACKET INCOMING" : "PACKET OUTGOING",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isIncoming ? Colors.green : Colors.blue,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    timeStr,
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Route: $transport (Hops: $hops)",
                                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          "Sender: ${log['sender']} ➜ Target: ${log['recipient']}",
                                          style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
                                        ),
                                        if (distance > 0) ...[
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              "WAN: ${distance.toStringAsFixed(0)} km",
                                              style: const TextStyle(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Text(
        title,
        style: TextStyle(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildTransportCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isActive,
    required String extra,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withOpacity(0.5) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? color.withOpacity(0.4) : (isDark ? Colors.white10 : Colors.black12),
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: isActive 
            ? [BoxShadow(color: color.withOpacity(0.1), blurRadius: 8, spreadRadius: 1)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: isActive ? color : Colors.grey, size: 24),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive ? color : Colors.grey.shade400,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      extra,
                      style: TextStyle(
                        color: isActive ? color.withOpacity(0.8) : Colors.grey,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassmorphicContainer({required bool isDark, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withOpacity(0.5) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: child,
        ),
      ),
    );
  }
}
