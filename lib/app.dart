import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'services/auth_service.dart';
import 'services/theme_notifier.dart';
import 'widgets/main_scaffold.dart';

class RoomiesApp extends StatefulWidget {
  const RoomiesApp({super.key});

  @override
  State<RoomiesApp> createState() => _RoomiesAppState();
}

class _RoomiesAppState extends State<RoomiesApp> {
  /// Only show the loading splash after 300 ms — avoids flicker on fast loads.
  bool _showSplash = false;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _showSplash = true);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seedColor = context.watch<ThemeNotifier>().seedColor;

    return MaterialApp(
      title: 'Roomies',
      debugShowCheckedModeBanner: false,

      // ─── Material 3 Theme ──────────────────────────────────────────────────
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
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
            // Only show branded splash after 300 ms — skip it on fast loads.
            if (!_showSplash) return const Scaffold(body: SizedBox.shrink());
            return const _SplashScreen();
          }
          return auth.currentUser != null
              ? const MainScaffold()
              : const LoginScreen();
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Text(
          'Roomies',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.primary,
              ),
        ),
      ),
    );
  }
}
