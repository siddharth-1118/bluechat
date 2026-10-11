import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/chat_message.dart';
import '../services/file_transfer_service.dart';
import '../services/bluetooth_service.dart';

class FileTransferWidget extends StatelessWidget {
  final ChatMessage message;

  const FileTransferWidget({Key? key, required this.message}) : super(key: key);

  IconData _getFileIcon(String? fileName) {
    if (fileName == null) return Icons.insert_drive_file;
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        return Icons.video_library;
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'flac':
        return Icons.audiotrack;
      case 'apk':
        return Icons.android;
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String? fileName) {
    if (fileName == null) return Colors.grey;
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Colors.redAccent;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return Colors.blueAccent;
      case 'mp4':
      case 'mov':
        return Colors.orangeAccent;
      case 'mp3':
      case 'wav':
        return Colors.purpleAccent;
      case 'apk':
        return Colors.greenAccent;
      case 'doc':
      case 'docx':
      case 'txt':
        return Colors.amberAccent;
      default:
        return Colors.blueGrey;
    }
  }

  void _openFile(BuildContext context) async {
    if (message.filePath == null) return;
    final file = File(message.filePath!);
    if (await file.exists()) {
      final ext = message.fileName?.split('.').last.toLowerCase() ?? '';
      if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp' || ext == 'gif') {
        try {
          final controller = MobileScannerController();
          final BarcodeCapture? capture = await controller.analyzeImage(message.filePath!);
          controller.dispose();

          if (capture != null && capture.barcodes.isNotEmpty) {
            final rawValue = capture.barcodes.first.rawValue;
            if (rawValue != null && rawValue.startsWith('upi://')) {
              _showUpiPaymentDialog(context, rawValue);
              return;
            }
          }
        } catch (e) {
          print("Error scanning image file for QR: $e");
        }
      }

      try {
        await OpenFilex.open(message.filePath!);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No app found to open this file format."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("File no longer exists locally."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _shareFile(BuildContext context) async {
    if (message.filePath == null) return;
    final file = File(message.filePath!);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("File no longer exists locally."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final mimeType = FileTransferService.getMimeType(message.fileName);
    final success = await BluetoothService.instance.shareFile(
      message.filePath!,
      mimeType: mimeType,
    );

    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not open the share sheet for this file."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showUpiPaymentDialog(BuildContext context, String upiUri) async {
    final uri = Uri.parse(upiUri);
    final payeeVpa = uri.queryParameters['pa'] ?? '';
    final payeeName = Uri.decodeComponent(uri.queryParameters['pn'] ?? 'Merchant/Payee');
    final note = Uri.decodeComponent(uri.queryParameters['tn'] ?? 'Payment via BlueChat');
    final initialAmount = uri.queryParameters['am'] ?? '';

    // Fetch installed UPI apps
    final upiApps = await BluetoothService.instance.getInstalledUpiApps();

    if (!context.mounted) return;

    if (upiApps.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("No UPI Apps Found", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            "Found UPI details ($payeeVpa), but no supported UPI apps (like Google Pay, PhonePe, Paytm) are installed on this device.",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK", style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );
      return;
    }

    final amountController = TextEditingController(text: initialAmount);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (dialogCtx, setState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
              titlePadding: const EdgeInsets.all(0),
              title: Container(
                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
                decoration: const BoxDecoration(
                  color: Colors.teal,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.security, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      "Secure UPI Payment",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      // Payee Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              payeeName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              payeeVpa,
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            if (note.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                "Note: $note",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Amount Section
                      Text(
                        "Amount to Pay (INR)",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark ? Colors.grey[300] : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 6),
                      initialAmount.isNotEmpty
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.teal.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.teal.withOpacity(0.3)),
                              ),
                              child: Text(
                                "₹ $initialAmount",
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                            )
                          : TextFormField(
                              controller: amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return "Please enter amount";
                                final amt = double.tryParse(val);
                                if (amt == null || amt <= 0) return "Enter a valid amount (> 0)";
                                return null;
                              },
                              decoration: InputDecoration(
                                prefixText: "₹ ",
                                prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Colors.teal, width: 2.0),
                                ),
                              ),
                            ),
                      const SizedBox(height: 20),
                      Text(
                        "Select App to Complete Payment",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark ? Colors.grey[300] : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // List of UPI apps
                      ...upiApps.map((app) {
                        final pkg = app['packageName'] ?? '';
                        final name = app['appName'] ?? 'UPI App';

                        Color appColor = Colors.teal;
                        IconData appIcon = Icons.account_balance;
                        if (pkg.contains("google.android.apps.nbu.paisa")) {
                          appColor = Colors.blue;
                          appIcon = Icons.payment;
                        } else if (pkg.contains("phonepe")) {
                          appColor = Colors.purple;
                          appIcon = Icons.account_balance_wallet;
                        } else if (pkg.contains("paytm")) {
                          appColor = Colors.cyan;
                          appIcon = Icons.credit_card;
                        } else if (pkg.contains("upiapp")) { // BHIM
                          appColor = Colors.orange;
                          appIcon = Icons.send;
                        } else if (pkg.contains("amazon")) {
                          appColor = Colors.amber[800]!;
                          appIcon = Icons.shopping_bag;
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: InkWell(
                            onTap: () async {
                              if (initialAmount.isEmpty && !formKey.currentState!.validate()) {
                                return;
                              }
                              final amt = amountController.text.trim();
                              // Build final URI
                              final finalUri = "upi://pay?pa=$payeeVpa&pn=${Uri.encodeComponent(payeeName)}&am=$amt&cu=INR&tn=${Uri.encodeComponent(note)}";
                              Navigator.pop(dialogCtx);

                              final success = await BluetoothService.instance.launchUpiPayment(finalUri, pkg);
                              if (!success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Could not launch payment app."),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: appColor.withOpacity(0.15),
                                    child: Icon(appIcon, color: appColor),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios, size: 14, color: isDark ? Colors.grey[600] : Colors.grey[400]),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final fileName = message.fileName ?? 'Unknown File';
    final totalSizeStr = message.fileSize != null 
        ? FileTransferService.getReadableFileSize(message.fileSize!) 
        : 'Unknown Size';

    final speedStr = FileTransferService.getReadableSpeed(message.fileTransferSpeed);
    final progressPct = (message.fileTransferProgress * 100).toStringAsFixed(0);
    final isSuccess = message.fileTransferStatus == 'success';
    final isFailed = message.fileTransferStatus == 'failed';
    final isTransferring = message.fileTransferStatus == 'transferring';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850]!.withOpacity(0.5) : Colors.grey[200],
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSuccess ? () => _openFile(context) : null,
          borderRadius: BorderRadius.circular(12.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: _getFileIconColor(fileName).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Icon(
                        _getFileIcon(fileName),
                        color: _getFileIconColor(fileName),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            totalSizeStr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSuccess)
                      const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20)
                    else if (isFailed)
                      const Icon(Icons.error, color: Colors.redAccent, size: 20),
                  ],
                ),
                if (isTransferring) ...[
                  const SizedBox(height: 12.0),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: LinearProgressIndicator(
                      value: message.fileTransferProgress,
                      backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "$progressPct%",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        speedStr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
                if (isFailed) ...[
                  const SizedBox(height: 6.0),
                  Text(
                    message.error ?? "Transfer failed.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.redAccent,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (isSuccess) ...[
                  const SizedBox(height: 8.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _shareFile(context),
                        icon: Icon(Icons.share, size: 16, color: isDark ? Colors.white70 : Colors.black54),
                        label: Text(
                          "Share",
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        "Tap to open",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      Icon(Icons.open_in_new, size: 12, color: theme.primaryColor),
                    ],
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}
