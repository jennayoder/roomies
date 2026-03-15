import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/theme_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase before the app starts.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Google Sign-In for Google Calendar OAuth.
  await GoogleSignIn.instance.initialize(
    clientId: '1059067392660-cigc9c67r7h2g4l984ojspsk9iq79rqi.apps.googleusercontent.com',
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(
          create: (_) => ThemeNotifier(const Color(0xFF6750A4)),
        ),
      ],
      child: const RoomiesApp(),
    ),
  );
}
