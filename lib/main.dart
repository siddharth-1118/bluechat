import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
import 'providers/profile_provider.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/call_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error handler — prevents uncaught exceptions from silently killing the app
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('=== FlutterError: ${details.exception}');
    debugPrint('=== Stack: ${details.stack}');
  };

  final profileProvider = ProfileProvider();
  await profileProvider.loadProfile();

  final chatProvider = ChatProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: profileProvider),
        ChangeNotifierProvider.value(value: chatProvider),
      ],
      child: const BlueChatApp(),
    ),
  );
}

class BlueChatApp extends StatelessWidget {
  const BlueChatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);

    // Dynamic accent color based on user selection
    final accentColor = Color(int.parse(profile.avatarColor, radix: 16));

    // Modern Deep Navy Dark Theme
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      primaryColor: accentColor,
      scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
      cardColor: const Color(0xFF1E293B),               // Slate 800
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E293B),
        elevation: 0,
        centerTitle: false,
      ),
      colorScheme: ColorScheme.dark(
        primary: accentColor,
        secondary: accentColor,
        surface: const Color(0xFF1E293B),
        background: const Color(0xFF0F172A),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(color: Colors.white60),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Colors.white),
        titleMedium: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Colors.white),
        bodyMedium: TextStyle(fontFamily: 'Inter', color: Colors.white70),
        bodySmall: TextStyle(fontFamily: 'Inter', color: Colors.white54),
      ),
    );

    // Clean Light Theme
    final lightTheme = ThemeData(
      brightness: Brightness.light,
      primaryColor: accentColor,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Slate 50
      cardColor: Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: accentColor,
        elevation: 0,
        centerTitle: false,
      ),
      colorScheme: ColorScheme.light(
        primary: accentColor,
        secondary: accentColor,
        surface: Colors.white,
        background: const Color(0xFFF8FAFC),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey[200],
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Colors.black87),
        titleMedium: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Colors.black87),
        bodyMedium: TextStyle(fontFamily: 'Inter', color: Colors.black87),
        bodySmall: TextStyle(fontFamily: 'Inter', color: Colors.black54),
      ),
    );

    return MaterialApp(
      title: 'BlueChat',
      debugShowCheckedModeBanner: false,
      theme: profile.isDarkMode ? darkTheme : lightTheme,
      home: profile.isSetupComplete ? const HomeScreen() : const ProfileSetupScreen(),
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const CallOverlay(),
          ],
        );
      },
    );
  }
}
