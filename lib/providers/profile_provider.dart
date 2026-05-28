import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileProvider with ChangeNotifier {
  String _username = '';
  String _avatarColor = 'FF10B981'; // Sleek Emerald Green default
  String _profilePhoto = '';        // Custom profile photo file path
  bool _isDarkMode = true;          // Modern look defaults to dark mode
  bool _isSetupComplete = false;
  String _phoneNumber = '';
  String _gmailAccount = '';
  List<String> _backupHistory = [];

  String get username => _username;
  String get avatarColor => _avatarColor;
  String get profilePhoto => _profilePhoto;
  bool get isDarkMode => _isDarkMode;
  bool get isSetupComplete => _isSetupComplete;
  String get phoneNumber => _phoneNumber;
  String get gmailAccount => _gmailAccount;
  List<String> get backupHistory => _backupHistory;

  Future<void> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('username') ?? '';
    _avatarColor = prefs.getString('avatar_color') ?? 'FF10B981';
    _profilePhoto = prefs.getString('profile_photo') ?? '';
    _isDarkMode = prefs.getBool('is_dark_mode') ?? true;
    _isSetupComplete = prefs.getBool('is_setup_complete') ?? false;
    _phoneNumber = prefs.getString('phone_number') ?? '';
    _gmailAccount = prefs.getString('gmail_account') ?? '';
    _backupHistory = prefs.getStringList('backup_history') ?? [];
    notifyListeners();
  }

  Future<void> saveProfile(String username, String hexColor, {String? profilePhotoPath, String? phone}) async {
    final prefs = await SharedPreferences.getInstance();
    String trimmedName = username.trim();
    if (!trimmedName.contains('#')) {
      final randomSuffix = (Random().nextInt(9000) + 1000).toString();
      trimmedName = '$trimmedName#$randomSuffix';
    }
    _username = trimmedName;
    _avatarColor = hexColor;
    if (profilePhotoPath != null) {
      _profilePhoto = profilePhotoPath;
      await prefs.setString('profile_photo', profilePhotoPath);
    }
    if (phone != null) {
      _phoneNumber = phone;
      await prefs.setString('phone_number', phone);
    }
    _isSetupComplete = true;
    await prefs.setString('username', _username);
    await prefs.setString('avatar_color', _avatarColor);
    await prefs.setBool('is_setup_complete', true);
    notifyListeners();
  }

  Future<void> linkGmail(String gmail) async {
    final prefs = await SharedPreferences.getInstance();
    _gmailAccount = gmail;
    await prefs.setString('gmail_account', gmail);
    notifyListeners();
  }

  Future<void> unlinkGmail() async {
    final prefs = await SharedPreferences.getInstance();
    _gmailAccount = '';
    await prefs.remove('gmail_account');
    notifyListeners();
  }

  Future<void> addBackupHistory(String logEntry) async {
    final prefs = await SharedPreferences.getInstance();
    _backupHistory.insert(0, logEntry);
    if (_backupHistory.length > 20) {
      _backupHistory = _backupHistory.sublist(0, 20);
    }
    await prefs.setStringList('backup_history', _backupHistory);
    notifyListeners();
  }

  Future<void> clearBackupHistory() async {
    final prefs = await SharedPreferences.getInstance();
    _backupHistory.clear();
    await prefs.remove('backup_history');
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = isDark;
    await prefs.setBool('is_dark_mode', isDark);
    notifyListeners();
  }
}
