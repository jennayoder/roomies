import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';

/// Manages Firebase Authentication state and exposes a stream of the current
/// user. Extends [ChangeNotifier] so that [Provider] can rebuild the widget
/// tree when auth state changes.
class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? _currentUser;

  AuthService() {
    // Read the synchronous cache immediately — avoids blank-screen delay on web.
    _currentUser = _auth.currentUser;

    // Then keep in sync with the async stream (handles sign-in/sign-out events).
    _auth.authStateChanges().listen((user) {
      _currentUser = user;
      notifyListeners();
    });
  }

  // ─── Getters ───────────────────────────────────────────────────────────────

  User? get currentUser => _currentUser;
  /// Always false now — we read the sync cache on construction.
  bool get isLoading => false;
  bool get isSignedIn => _currentUser != null;

  // ─── Registration ──────────────────────────────────────────────────────────

  /// Creates a new Firebase Auth account and writes a Firestore user profile.
  ///
  /// Throws [FirebaseAuthException] on failure.
  Future<UserModel> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = credential.user!.uid;

    // Update the Auth display name as well.
    await credential.user!.updateDisplayName(displayName);

    final profile = UserModel(
      uid: uid,
      displayName: displayName,
      email: email,
      createdAt: DateTime.now(),
    );

    await _db.collection('users').doc(uid).set(profile.toMap());
    return profile;
  }

  // ─── Sign in ───────────────────────────────────────────────────────────────

  /// Signs in with email and password.
  ///
  /// Throws [FirebaseAuthException] on failure.
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    // Ensure a Firestore user doc exists (creates one if missing).
    final uid = credential.user!.uid;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) {
      final displayName = credential.user!.displayName ??
          credential.user!.email?.split('@').first ??
          'User';
      final profile = UserModel(
        uid: uid,
        displayName: displayName,
        email: credential.user!.email ?? '',
        createdAt: DateTime.now(),
      );
      await _db.collection('users').doc(uid).set(profile.toMap());
    }
  }

  // ─── Sign out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ─── Password reset ────────────────────────────────────────────────────────

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ─── Firestore user profile ────────────────────────────────────────────────

  /// Fetches the Firestore profile for the currently signed-in user.
  Future<UserModel?> fetchUserProfile() async {
    if (_currentUser == null) return null;
    final doc = await _db.collection('users').doc(_currentUser!.uid).get();
    if (!doc.exists) return null;
    return UserModel.fromDoc(doc);
  }

  /// Returns a real-time stream of the current user's Firestore profile.
  Stream<UserModel?> userProfileStream() {
    if (_currentUser == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(_currentUser!.uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromDoc(doc) : null);
  }
}
