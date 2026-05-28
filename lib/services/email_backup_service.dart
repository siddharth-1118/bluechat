import 'dart:io';
import 'package:path/path.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailBackupService {
  EmailBackupService._privateConstructor();
  static final EmailBackupService instance = EmailBackupService._privateConstructor();

  // --- DEVELOPER SMTP CONFIGURATION ---
  // Paste your sender Gmail address and Google App Password (16 characters) below.
  // Once configured, the app will automatically send real email OTPs and backup file attachments.
  static const String smtpHost = "smtp.gmail.com";
  static const int smtpPort = 465; // SSL port (or 587 for STARTTLS)
  static const String smtpUsername = "saisiddharthvooka@gmail.com";
  static const String smtpPassword = "qbyzpducjvfpqjjn";

  /// Check if developer SMTP credentials are set and not defaults.
  bool get isConfigured =>
      smtpUsername.isNotEmpty &&
      smtpPassword.isNotEmpty &&
      smtpUsername != "your-sender-email@gmail.com" &&
      smtpPassword != "your-app-password";

  /// Sends a 6-digit OTP code to the recipient's Gmail address.
  Future<void> sendOtpEmail(String recipientEmail, String otpCode) async {
    if (!isConfigured) {
      print("EmailBackupService: [SIMULATION MODE] Generated OTP is: $otpCode");
      print("EmailBackupService: [SIMULATION MODE] Print code to console since SMTP credentials are not configured.");
      await Future.delayed(const Duration(seconds: 1)); // Simulate network latency
      return;
    }

    final smtpServer = gmail(smtpUsername.trim(), smtpPassword.trim());

    final message = Message()
      ..from = Address(smtpUsername, 'BlueChat Backup Manager')
      ..recipients.add(recipientEmail.trim())
      ..subject = 'BlueChat Backup Verification Code'
      ..text = 'Hello,\n\nYour verification code for BlueChat Gmail Backup is: $otpCode\n\nPlease enter this code in the app to link your Gmail account.\n\nRegards,\nBlueChat Team'
      ..html = '''
        <h3>BlueChat Gmail Backup Verification</h3>
        <p>Hello,</p>
        <p>Your verification code for BlueChat Gmail Backup is: <b><font size="5" color="#2563EB">$otpCode</font></b></p>
        <p>Please enter this code in the app to link your Gmail account and enable secure cloud backups.</p>
        <br>
        <p>Regards,<br>BlueChat Team</p>
      ''';

    try {
      await send(message, smtpServer);
      print("EmailBackupService: Verification code email sent to $recipientEmail successfully.");
    } on MailerException catch (e) {
      print("EmailBackupService: Failed to send OTP email: $e");
      for (var p in e.problems) {
        print("Problem: ${p.code}: ${p.msg}");
      }
      throw Exception("SMTP Delivery Failed: ${e.message}");
    } catch (e) {
      print("EmailBackupService: Failed to send OTP email: $e");
      throw Exception("Failed to dispatch email: $e");
    }
  }

  /// Sends the encrypted backup file as an attachment to the recipient's Gmail address.
  Future<void> sendBackupEmail(String recipientEmail, File backupFile) async {
    if (!isConfigured) {
      print("EmailBackupService: [SIMULATION MODE] Emailed encrypted backup file to: $recipientEmail");
      await Future.delayed(const Duration(seconds: 1)); // Simulate network latency
      return;
    }

    final smtpServer = gmail(smtpUsername.trim(), smtpPassword.trim());

    final message = Message()
      ..from = Address(smtpUsername, 'BlueChat Backup Manager')
      ..recipients.add(recipientEmail.trim())
      ..subject = 'BlueChat Database Backup'
      ..text = 'Hello,\n\nAttached is your secure, encrypted BlueChat chat backup.\n\nTo restore your chats in the future, save the attached "bluechat_backup.json" file to your device. Then, in the app, click "Restore Chats" and select the file using the import option.\n\nRegards,\nBlueChat Team'
      ..html = '''
        <h3>BlueChat Chat Database Backup</h3>
        <p>Hello,</p>
        <p>Attached is your secure, encrypted BlueChat chat database backup.</p>
        <p>To restore your chats in the future:</p>
        <ol>
          <li>Download/save the attached <b>bluechat_backup.json</b> file to your device.</li>
          <li>In the BlueChat app, open <b>Gmail Backup Center</b>.</li>
          <li>Click <b>Restore Chats</b> and choose the <b>Import from downloaded file</b> option.</li>
          <li>Select the downloaded file to recover all your messages and settings.</li>
        </ol>
        <br>
        <p>Regards,<br>BlueChat Team</p>
      '''
      ..attachments.add(FileAttachment(backupFile));

    try {
      await send(message, smtpServer);
      print("EmailBackupService: Backup database email sent successfully to $recipientEmail.");
    } on MailerException catch (e) {
      print("EmailBackupService: Failed to send backup email: $e");
      for (var p in e.problems) {
        print("Problem: ${p.code}: ${p.msg}");
      }
      throw Exception("SMTP Backup Delivery Failed: ${e.message}");
    } catch (e) {
      print("EmailBackupService: Failed to send backup email: $e");
      throw Exception("Failed to dispatch backup email: $e");
    }
  }

  Future<void> downloadBackupEmail(String gmailAccount, File targetFile) async {
    final tempDir = Directory.systemTemp;
    final localBackup = File(join(tempDir.path, "bluechat_backup.enc"));
    if (localBackup.existsSync()) {
      await localBackup.copy(targetFile.path);
      print("EmailBackupService: [SIMULATION] Downloaded backup from Gmail (copied from local cache).");
    } else {
      throw Exception("No backup found on Gmail server for $gmailAccount");
    }
  }
}
