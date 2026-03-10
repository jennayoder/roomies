// GENERATED FILE — DO NOT EDIT MANUALLY
//
// Firebase configuration for roomies-6d591

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB1Mdfnu4UzPthpfzC2fjxCJfpXSHO5-Kw',
    appId: '1:194387085212:web:cce378dd2e3cefeb3d6a59',
    messagingSenderId: '194387085212',
    projectId: 'roomies-6d591',
    authDomain: 'roomies-6d591.firebaseapp.com',
    storageBucket: 'roomies-6d591.firebasestorage.app',
    measurementId: 'G-GMTK09Z7FV',
  );

  // Android/iOS: register separate apps in Firebase Console to get platform-specific appIds
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB1Mdfnu4UzPthpfzC2fjxCJfpXSHO5-Kw',
    appId: '1:194387085212:web:cce378dd2e3cefeb3d6a59',
    messagingSenderId: '194387085212',
    projectId: 'roomies-6d591',
    storageBucket: 'roomies-6d591.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB1Mdfnu4UzPthpfzC2fjxCJfpXSHO5-Kw',
    appId: '1:194387085212:web:cce378dd2e3cefeb3d6a59',
    messagingSenderId: '194387085212',
    projectId: 'roomies-6d591',
    storageBucket: 'roomies-6d591.firebasestorage.app',
    iosClientId: '',
    iosBundleId: 'com.example.roomies',
  );
}
