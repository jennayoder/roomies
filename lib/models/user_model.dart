import 'package:cloud_firestore/cloud_firestore.dart';

/// App-level user profile stored in Firestore at /users/{uid}.
///
/// This is separate from Firebase Auth's User object — it holds additional
/// profile information like display name, avatar color, and which household
/// the user currently belongs to.
class UserModel {
  final String uid;
  final String displayName;
  final String email;

  /// The household this user is currently a member of (null if none).
  final String? householdId;

  /// A hex color string (e.g. '#6750A4') used for the user's avatar.
  final String avatarColor;

  final DateTime createdAt;

  // ─── XP / Gamification fields ──────────────────────────────────────────────

  final int totalXp;
  final int level;

  /// Currently equipped avatar emoji (e.g. '🔑').
  final String? currentAvatar;

  /// Currently applied theme color hex (e.g. '#6750A4').
  final String? currentTheme;

  /// Title earned at current level (e.g. 'Reliable Roomie').
  final String? title;

  /// List of avatar emojis the user has unlocked.
  final List<String> unlockedAvatars;

  /// List of hex color strings for themes the user has unlocked.
  final List<String> unlockedThemes;

  /// Set by XpService when the user levels up; cleared after dialog is shown.
  final int? pendingLevelUp;

  const UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    this.householdId,
    this.avatarColor = '#6750A4',
    required this.createdAt,
    this.totalXp = 0,
    this.level = 1,
    this.currentAvatar,
    this.currentTheme,
    this.title,
    this.unlockedAvatars = const [],
    this.unlockedThemes = const [],
    this.pendingLevelUp,
  });

  // ─── Firestore serialization ───────────────────────────────────────────────

  factory UserModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      displayName: data['displayName'] as String,
      email: data['email'] as String,
      householdId: data['householdId'] as String?,
      avatarColor: (data['avatarColor'] as String?) ?? '#6750A4',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      totalXp: (data['totalXp'] as int?) ?? 0,
      level: (data['level'] as int?) ?? 1,
      currentAvatar: data['currentAvatar'] as String?,
      currentTheme: data['currentTheme'] as String?,
      title: data['title'] as String?,
      unlockedAvatars: List<String>.from(data['unlockedAvatars'] ?? const []),
      unlockedThemes: List<String>.from(data['unlockedThemes'] ?? const []),
      pendingLevelUp: data['pendingLevelUp'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'email': email,
        'householdId': householdId,
        'avatarColor': avatarColor,
        'createdAt': Timestamp.fromDate(createdAt),
        'totalXp': totalXp,
        'level': level,
        'currentAvatar': currentAvatar,
        'currentTheme': currentTheme,
        'title': title,
        'unlockedAvatars': unlockedAvatars,
        'unlockedThemes': unlockedThemes,
        'pendingLevelUp': pendingLevelUp,
      };

  UserModel copyWith({
    String? displayName,
    String? householdId,
    String? avatarColor,
    int? totalXp,
    int? level,
    String? currentAvatar,
    String? currentTheme,
    String? title,
    List<String>? unlockedAvatars,
    List<String>? unlockedThemes,
    int? pendingLevelUp,
  }) =>
      UserModel(
        uid: uid,
        displayName: displayName ?? this.displayName,
        email: email,
        householdId: householdId ?? this.householdId,
        avatarColor: avatarColor ?? this.avatarColor,
        createdAt: createdAt,
        totalXp: totalXp ?? this.totalXp,
        level: level ?? this.level,
        currentAvatar: currentAvatar ?? this.currentAvatar,
        currentTheme: currentTheme ?? this.currentTheme,
        title: title ?? this.title,
        unlockedAvatars: unlockedAvatars ?? this.unlockedAvatars,
        unlockedThemes: unlockedThemes ?? this.unlockedThemes,
        pendingLevelUp: pendingLevelUp ?? this.pendingLevelUp,
      );
}
