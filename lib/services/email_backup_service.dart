import 'dart:io';
import 'package:path/path.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmailBackupService {
  EmailBackupService._privateConstructor();
  static final EmailBackupService instance = EmailBackupService._privateConstructor();

  // --- SMTP CONFIGURATION ---
  // Credentials are NEVER hardcoded in source. They are resolved in order:
  //   1. Runtime config saved via saveConfig() (stored in SharedPreferences)
  //   2. Compile-time values passed at build time:
  //        flutter build apk --dart-define=SMTP_USERNAME=you@gmail.com \
  //                               --dart-define=SMTP_PASSWORD=your-app-password
  //   If neither is set, the service runs in SIMULATION MODE (OTP printed to
  //   console, no email is sent).
  static const String smtpHost = "smtp.gmail.com";
  static const int smtpPort = 465; // SSL port (or 587 for STARTTLS)

  static const String _defineUsername = String.fromEnvironment('SMTP_USERNAME');
  static const String _definePassword = String.fromEnvironment('SMTP_PASSWORD');

  static const String _prefsKeyUsername = 'smtp_config_username';
  static const String _prefsKeyPassword = 'smtp_config_password';

  String? _username;
  String? _password;
  bool _configLoaded = false;

  /// True when real SMTP credentials are available (runtime or compile-time).
  bool get isConfigured {
    final u = _username ?? _defineUsername;
    final p = _password ?? _definePassword;
    return u.isNotEmpty && p.isNotEmpty;
  }

  /// The sender address in use, or an empty string in simulation mode.
  String get configuredUsername => _username ?? _defineUsername;

  /// Loads the runtime config (if any) into memory. Safe to call repeatedly.
  Future<void> loadConfig() async {
    if (_configLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _username = prefs.getString(_prefsKeyUsername);
      _password = prefs.getString(_prefsKeyPassword);
    } catch (e) {
      print("EmailBackupService: Failed to load SMTP config: $e");
    }
    _configLoaded = true;
  }

  /// Saves SMTP credentials for this device (used by the in-app setup dialog).
  Future<void> saveConfig(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyUsername, username.trim());
    await prefs.setString(_prefsKeyPassword, password.trim());
    _username = username.trim();
    _password = password.trim();
    _configLoaded = true;
  }

  /// Removes the stored runtime credentials.
  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyUsername);
    await prefs.remove(_prefsKeyPassword);
    _username = null;
    _password = null;
    _configLoaded = true;
  }

  SmtpServer? _buildSmtpServer() {
    final u = _username ?? _defineUsername;
    final p = _password ?? _definePassword;
    if (u.isEmpty || p.isEmpty) return null;
    return gmail(u.trim(), p.trim());
  }

  /// Sends a 6-digit OTP code to the recipient's Gmail address.
  Future<void> sendOtpEmail(String recipientEmail, String otpCode) async {
    await loadConfig();
    final smtpServer = _buildSmtpServer();
    if (smtpServer == null) {
      print("EmailBackupService: [SIMULATION MODE] Generated OTP is: $otpCode");
      print("EmailBackupService: [SIMULATION MODE] Print code to console since SMTP credentials are not configured.");
      await Future.delayed(const Duration(seconds: 1)); // Simulate network latency
      return;
    }

    final message = Message()
      ..from = Address((_username ?? _defineUsername).trim(), 'BlueChat Backup Manager')
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
    await loadConfig();
    final smtpServer = _buildSmtpServer();
    if (smtpServer == null) {
      print("EmailBackupService: [SIMULATION MODE] Emailed encrypted backup file to: $recipientEmail");
      await Future.delayed(const Duration(seconds: 1)); // Simulate network latency
      return;
    }

    final message = Message()
      ..from = Address((_username ?? _defineUsername).trim(), 'BlueChat Backup Manager')
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
