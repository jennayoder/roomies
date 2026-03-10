import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'services/auth_service.dart';
import 'widgets/main_scaffold.dart';

class RoomiesApp extends StatelessWidget {
  const RoomiesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roomies',
      debugShowCheckedModeBanner: false,

      // ─── Material 3 Theme ──────────────────────────────────────────────────
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4), // M3 default purple
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
      ),
      themeMode: ThemeMode.system,

      // ─── Named Routes ──────────────────────────────────────────────────────
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const MainScaffold(),
      },

      // ─── Root: decide whether to show auth or main app ────────────────────
      home: Consumer<AuthService>(
        builder: (context, auth, _) {
          if (auth.isLoading) {
            // Splash / loading state while Firebase Auth resolves
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return auth.currentUser != null
              ? const MainScaffold()
              : const LoginScreen();
        },
      ),
    );
  }
}
