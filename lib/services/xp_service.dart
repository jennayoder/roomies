import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/level_system.dart';

/// Awards XP to users and handles level-up detection.
///
/// All mutations run inside a Firestore transaction so concurrent awards
/// can't corrupt the XP total.
class XpService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int _rentOnTimeXp = 20;
  static const int _expensePaidXp = 100;
  static const int _choreCompletedXp = 50;

  Future<void> awardRentPaidOnTime(String uid, String householdId) =>
      _addXp(uid, _rentOnTimeXp, source: 'rent', description: 'Paid rent on time 🏠');

  Future<void> awardExpensePaid(String uid, String householdId) =>
      _addXp(uid, _expensePaidXp, source: 'expense', description: 'Settled an expense 💸');

  Future<void> awardChoreCompleted(String uid, String householdId, {int? xp, String? choreTitle}) =>
      _addXp(uid, xp ?? _choreCompletedXp, source: 'chore',
          description: choreTitle != null ? 'Completed: $choreTitle 🧹' : 'Completed a chore 🧹');

  Future<void> awardPersonalTaskCompleted(
    String uid,
    String householdId,
    int taskXp, {
    String? taskTitle,
  }) =>
      _addXp(uid, taskXp.clamp(50, 1000), source: 'task',
          description: taskTitle != null ? 'Completed task: $taskTitle ⭐' : 'Completed a task ⭐');

  Future<void> _addXp(String uid, int amount, {String source = 'other', String description = 'XP earned'}) async {
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      if (!snap.exists) return;

      final data = snap.data() as Map<String, dynamic>;
      final oldXp = (data['totalXp'] as int?) ?? 0;
      final oldLevel = (data['level'] as int?) ?? 1;

      final newXp = oldXp + amount;
      final newLevel = LevelSystem.fromXp(newXp);

      final updates = <String, dynamic>{
        'totalXp': newXp,
        'level': newLevel,
      };

      if (newLevel > oldLevel) {
        final newInfo = LevelSystem.infoFor(newLevel);
        final avatars = LevelSystem.avatarsUnlockedAt(newLevel);
        final themes = LevelSystem.themesUnlockedAt(newLevel)
            .map(LevelSystem.colorToHex)
            .toList();

        updates['title'] = newInfo.title;
        updates['unlockedAvatars'] = avatars;
        updates['unlockedThemes'] = themes;
        // Notify the app to show the level-up celebration dialog.
        updates['pendingLevelUp'] = newLevel;
        // Auto-equip the newly unlocked avatar.
        updates['currentAvatar'] = newInfo.avatarEmoji;
      }

      tx.update(userRef, updates);
    });

    // Log XP history entry (outside transaction, best-effort)
    await _db.collection('users').doc(uid).collection('xp_history').add({
      'amount': amount,
      'source': source,
      'description': description,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Clears the pending level-up flag after the dialog has been shown.
  Future<void> clearPendingLevelUp(String uid) async {
    await _db.collection('users').doc(uid).update({'pendingLevelUp': null});
  }

  /// Updates the user's chosen avatar (must be in unlockedAvatars).
  Future<void> setAvatar(String uid, String avatarEmoji) async {
    await _db.collection('users').doc(uid).update({'currentAvatar': avatarEmoji});
  }

  /// Updates the user's chosen theme color (hex string).
  Future<void> setTheme(String uid, String hexColor) async {
    await _db.collection('users').doc(uid).update({'currentTheme': hexColor});
  }
}
