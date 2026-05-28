import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/profile_provider.dart';
import '../database/database_helper.dart';
import 'home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({Key? key}) : super(key: key);

  @override
  _ProfileSetupScreenState createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _profilePhotoPath;
  late String _usernameSuffix;
  List<String> _takenUsernames = [];
  
  final List<String> _colors = [
    'FF10B981', // Emerald
    'FF3B82F6', // Blue
    'FF8B5CF6', // Purple
    'FFEF4444', // Red
    'FFF59E0B', // Amber
    'FFEC4899', // Pink
    'FFF97316', // Orange
    'FF06B6D4', // Cyan
  ];

  late String _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = _colors.first;
    _usernameSuffix = (Random().nextInt(9000) + 1000).toString();
    _loadExistingPeers();
  }

  Future<void> _loadExistingPeers() async {
    try {
      final peers = await DatabaseHelper.instance.getPeers();
      setState(() {
        _takenUsernames = peers.map((p) => p.name.toLowerCase()).toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Card(
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
                color: isDark ? const Color(0xFF1E293B).withOpacity(0.85) : Colors.white.withOpacity(0.95),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Profile Photo Picker
                        GestureDetector(
                          onTap: () async {
                            final result = await FilePicker.platform.pickFiles(type: FileType.image);
                            if (result != null && result.files.single.path != null) {
                              setState(() {
                                _profilePhotoPath = result.files.single.path!;
                              });
                            }
                          },
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 54,
                                backgroundColor: Color(int.parse(_selectedColor, radix: 16)).withOpacity(0.15),
                                backgroundImage: _profilePhotoPath != null
                                    ? FileImage(File(_profilePhotoPath!))
                                    : null,
                                child: _profilePhotoPath == null
                                    ? Icon(
                                        Icons.person,
                                        size: 54,
                                        color: Color(int.parse(_selectedColor, radix: 16)),
                                      )
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Color(int.parse(_selectedColor, radix: 16)),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: isDark ? const Color(0xFF1E293B) : Colors.white, width: 2.0),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24.0),
                        Text(
                          "Welcome to BlueChat",
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8.0),
                        Text(
                          "Set up your local offline profile to begin chatting",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 32.0),
                        // Username Field
                        TextFormField(
                          controller: _usernameController,
                          maxLength: 15,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            labelText: "Username",
                            labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                            hintText: "Enter your display name",
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                            prefixIcon: Icon(Icons.person, color: Color(int.parse(_selectedColor, radix: 16))),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(
                                  color: Color(int.parse(_selectedColor, radix: 16)),
                                  width: 2.0,
                                ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return "Username cannot be empty";
                            }
                            if (value.trim().length < 3) {
                              return "Must be at least 3 characters";
                            }
                            final enteredName = value.trim().toLowerCase();
                            if (_takenUsernames.contains(enteredName) || 
                                _takenUsernames.contains("$enteredName#$_usernameSuffix")) {
                              return "This username is already taken by a contact";
                            }
                            return null;
                          },
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _usernameController,
                          builder: (context, value, child) {
                            final name = value.text.trim();
                            if (name.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                              child: Text(
                                "Your unique tag: $name#$_usernameSuffix",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Color(int.parse(_selectedColor, radix: 16)),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16.0),
                        // Phone Number Field
                        TextFormField(
                          controller: _phoneController,
                          maxLength: 15,
                          keyboardType: TextInputType.phone,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            labelText: "Mobile Phone Number",
                            labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                            hintText: "e.g. +91 98765 43210",
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                            prefixIcon: Icon(Icons.phone, color: Color(int.parse(_selectedColor, radix: 16))),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(
                                  color: Color(int.parse(_selectedColor, radix: 16)),
                                  width: 2.0,
                                ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return "Phone number cannot be empty";
                            }
                            final cleanVal = value.replaceAll(RegExp(r'\D'), '');
                            if (cleanVal.length < 6) {
                              return "Enter a valid phone number";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16.0),
                        // Color Selector
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Select Theme Color",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12.0),
                        SizedBox(
                          height: 48,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _colors.length,
                            itemBuilder: (context, index) {
                              final colorHex = _colors[index];
                              final isSelected = colorHex == _selectedColor;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedColor = colorHex;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 6.0),
                                  width: 42,
                                  decoration: BoxDecoration(
                                    color: Color(int.parse(colorHex, radix: 16)),
                                    shape: BoxShape.circle,
                                    border: isSelected
                                        ? Border.all(
                                            color: isDark ? Colors.white : Colors.black87,
                                            width: 3.0,
                                          )
                                        : null,
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: Color(int.parse(colorHex, radix: 16)).withOpacity(0.5),
                                              blurRadius: 8,
                                              spreadRadius: 2,
                                            )
                                          ]
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 36.0),
                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(int.parse(_selectedColor, radix: 16)),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                              elevation: 4,
                            ),
                            onPressed: () async {
                              if (_formKey.currentState!.validate()) {
                                final profile = Provider.of<ProfileProvider>(context, listen: false);
                                await profile.saveProfile(
                                  "${_usernameController.text.trim()}#$_usernameSuffix",
                                  _selectedColor,
                                  profilePhotoPath: _profilePhotoPath,
                                  phone: _phoneController.text.trim(),
                                );
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                                );
                              }
                            },
                            child: const Text(
                              "Get Started",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
