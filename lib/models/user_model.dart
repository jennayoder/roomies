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

  const UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    this.householdId,
    this.avatarColor = '#6750A4',
    required this.createdAt,
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
    );
  }

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'email': email,
        'householdId': householdId,
        'avatarColor': avatarColor,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  UserModel copyWith({
    String? displayName,
    String? householdId,
    String? avatarColor,
  }) =>
      UserModel(
        uid: uid,
        displayName: displayName ?? this.displayName,
        email: email,
        householdId: householdId ?? this.householdId,
        avatarColor: avatarColor ?? this.avatarColor,
        createdAt: createdAt,
      );
}
