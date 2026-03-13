import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/chore.dart';
import '../models/chore_completion.dart';
import '../models/event.dart';
import '../models/expense.dart';
import '../models/household.dart';
import '../models/rent_entry.dart';
import '../models/user_model.dart';
import 'xp_service.dart';

/// Generic Firestore helpers for the household's feature sub-collections.
///
/// All methods take the [householdId] explicitly so they can be called from
/// any screen without needing a BuildContext-level household reference.
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  // ─── Collection references ─────────────────────────────────────────────────

  CollectionReference _rent(String householdId) =>
      _db.collection('households').doc(householdId).collection('rent');

  CollectionReference _expenses(String householdId) =>
      _db.collection('households').doc(householdId).collection('expenses');

  CollectionReference _chores(String householdId) =>
      _db.collection('households').doc(householdId).collection('chores');

  CollectionReference _events(String householdId) =>
      _db.collection('households').doc(householdId).collection('events');

  // ─── Rent ──────────────────────────────────────────────────────────────────

  Stream<List<RentEntry>> rentStream(String householdId) {
    return _rent(householdId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(RentEntry.fromDoc).toList());
  }

  Future<void> addRentEntry(String householdId, RentEntry entry) async {
    await _rent(householdId).doc(entry.id).set(entry.toMap());
  }

  Future<void> markRentPaid(String householdId, String entryId) async {
    await _rent(householdId).doc(entryId).update({'isFullyPaid': true});
    await XpService().awardRentPaidOnTime(_uid, householdId);
  }

  Future<void> deleteRentEntry(String householdId, String entryId) async {
    await _rent(householdId).doc(entryId).delete();
  }

  /// Marks a specific member's share as paid and awards 20 XP.
  /// Checks if all members have paid; if so, marks the entry fully paid.
  Future<void> markMemberRentPaid(
      String householdId, String entryId, String uid) async {
    final ref = _rent(householdId).doc(entryId);
    final doc = await ref.get();
    if (!doc.exists) return;

    final entry = RentEntry.fromDoc(doc);
    final newPaidStatus = Map<String, bool>.from(entry.paidStatus)
      ..[uid] = true;

    final allPaid =
        entry.memberShares.keys.every((k) => newPaidStatus[k] == true);

    await ref.update({
      'paidStatus.$uid': true,
      if (allPaid) 'isFullyPaid': true,
    });

    await XpService().awardRentPaidOnTime(uid, householdId);
  }

  // ─── Expenses ──────────────────────────────────────────────────────────────

  Stream<List<Expense>> expensesStream(String householdId) {
    return _expenses(householdId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Expense.fromDoc).toList());
  }

  Future<void> addExpense(String householdId, Expense expense) async {
    await _expenses(householdId).doc(expense.id).set(expense.toMap());
  }

  Future<void> settleExpense(String householdId, String expenseId) async {
    final doc = await _expenses(householdId).doc(expenseId).get();
    final paidById =
        doc.exists ? (doc.data() as Map<String, dynamic>)['paidById'] as String? : null;
    await _expenses(householdId).doc(expenseId).update({'isSettled': true});
    if (paidById != null) {
      await XpService().awardExpensePaid(paidById, householdId);
    }
  }

  Future<void> deleteExpense(String householdId, String expenseId) async {
    await _expenses(householdId).doc(expenseId).delete();
  }

  /// Marks one member's portion of an expense as paid.
  /// If all members have paid, marks the whole expense as settled.
  Future<void> markExpenseMemberPaid(
      String householdId, String expenseId, String uid) async {
    final ref = _expenses(householdId).doc(expenseId);
    final doc = await ref.get();
    if (!doc.exists) return;

    final expense = Expense.fromDoc(doc);
    final newPaidStatus = Map<String, bool>.from(expense.paidStatus)
      ..[uid] = true;

    final allPaid =
        expense.memberAmounts.keys.every((k) => newPaidStatus[k] == true);

    await ref.update({
      'paidStatus.$uid': true,
      if (allPaid) 'isSettled': true,
    });

    await XpService().awardExpensePaid(uid, householdId);
  }

  // ─── Chores ────────────────────────────────────────────────────────────────

  Stream<List<Chore>> choresStream(String householdId) {
    return _chores(householdId)
        .orderBy('dueDate')
        .snapshots()
        .map((s) => s.docs.map(Chore.fromDoc).toList());
  }

  Future<void> addChore(String householdId, Chore chore) async {
    await _chores(householdId).doc(chore.id).set(chore.toMap());
  }

  Future<void> toggleChoreComplete(
    String householdId,
    String choreId,
    bool isCompleted,
  ) async {
    String? assignedToId;
    if (isCompleted) {
      final doc = await _chores(householdId).doc(choreId).get();
      if (doc.exists) {
        assignedToId =
            (doc.data() as Map<String, dynamic>)['assignedToId'] as String?;
      }
    }
    int xpReward = 25;
    String? choreTitle;
    if (isCompleted) {
      final doc = await _chores(householdId).doc(choreId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        assignedToId ??= data['assignedToId'] as String?;
        xpReward = (data['xpReward'] as int?) ?? 25;
        choreTitle = data['title'] as String?;
      }
    }
    await _chores(householdId).doc(choreId).update({
      'isCompleted': isCompleted,
      'completedAt': isCompleted ? Timestamp.now() : null,
    });
    if (isCompleted && assignedToId != null) {
      await XpService().awardChoreCompleted(assignedToId, householdId,
          xp: xpReward, choreTitle: choreTitle);
    }
  }

  Future<void> claimChore(String householdId, String choreId, String uid) async {
    await _chores(householdId).doc(choreId).update({'assignedToId': uid});
  }

  Future<void> deleteChore(String householdId, String choreId) async {
    await _chores(householdId).doc(choreId).delete();
  }

  /// Logs a repeatable chore completion without marking it done.
  Future<void> claimRepeatableChore(
    String householdId,
    String choreId,
    String uid,
    String displayName, {
    int xpReward = 25,
    String? choreTitle,
  }) async {
    await _chores(householdId)
        .doc(choreId)
        .collection('completions')
        .add(ChoreCompletion(
          id: '',
          uid: uid,
          displayName: displayName,
          claimedAt: DateTime.now(),
        ).toMap());

    await XpService().awardChoreCompleted(uid, householdId,
        xp: xpReward, choreTitle: choreTitle);
  }

  /// Streams recent completions for a repeatable chore (last 20).
  Stream<List<ChoreCompletion>> choreCompletionsStream(
      String householdId, String choreId) {
    return _chores(householdId)
        .doc(choreId)
        .collection('completions')
        .orderBy('claimedAt', descending: true)
        .limit(20)
        .snapshots()
        .map((s) => s.docs.map(ChoreCompletion.fromDoc).toList());
  }

  // ─── Events ────────────────────────────────────────────────────────────────

  Stream<List<Event>> eventsStream(String householdId) {
    return _events(householdId)
        .orderBy('dateTime')
        .snapshots()
        .map((s) => s.docs.map(Event.fromDoc).toList());
  }

  Future<void> addEvent(String householdId, Event event) async {
    await _events(householdId).doc(event.id).set(event.toMap());
  }

  /// Toggles the current user's RSVP for an event.
  Future<void> rsvpEvent(
    String householdId,
    String eventId,
    bool attending,
  ) async {
    await _events(householdId).doc(eventId).update({
      'attendeeIds': attending
          ? FieldValue.arrayUnion([_uid])
          : FieldValue.arrayRemove([_uid]),
    });
  }

  Future<void> deleteEvent(String householdId, String eventId) async {
    await _events(householdId).doc(eventId).delete();
  }

  // ─── Member management ─────────────────────────────────────────────────────

  /// Fetches all members of [householdId] with their roles.
  ///
  /// Returns a list of (UserModel, HouseholdRole) pairs.
  Future<List<(UserModel, HouseholdRole)>> getHouseholdMembers(
    String householdId,
  ) async {
    final doc =
        await _db.collection('households').doc(householdId).get();
    if (!doc.exists) return [];
    final household = Household.fromDoc(doc);

    final profiles = await Future.wait(
      household.memberIds.map((uid) => _db.collection('users').doc(uid).get()),
    );

    final result = <(UserModel, HouseholdRole)>[];
    for (int i = 0; i < profiles.length; i++) {
      final snap = profiles[i];
      final uid = household.memberIds[i];
      final role = household.members[uid];
      if (role == null) continue;

      if (snap.exists) {
        result.add((UserModel.fromDoc(snap), role));
      } else {
        // User doc missing — create a stub so they still show up,
        // and write a real doc so it's fixed for next time.
        final stub = UserModel(
          uid: uid,
          displayName: 'Member',
          email: '',
          createdAt: DateTime.now(),
        );
        // Write stub silently in background
        _db.collection('users').doc(uid).set(stub.toMap());
        result.add((stub, role));
      }
    }
    return result;
  }

  /// Updates the role of [uid] in [householdId].
  Future<void> updateMemberRole(
    String householdId,
    String uid,
    HouseholdRole role,
  ) async {
    await _db.collection('households').doc(householdId).update({
      'members.$uid': role.name,
    });
  }

  /// Removes [uid] from [householdId] and clears their householdId.
  Future<void> removeMember(String householdId, String uid) async {
    final batch = _db.batch();
    batch.update(_db.collection('households').doc(householdId), {
      'members.$uid': FieldValue.delete(),
      'memberIds': FieldValue.arrayRemove([uid]),
    });
    batch.update(_db.collection('users').doc(uid), {
      'householdId': FieldValue.delete(),
    });
    await batch.commit();
  }

  /// Returns the invite code for [householdId], or null if not found.
  Future<String?> getInviteCode(String householdId) async {
    final doc =
        await _db.collection('households').doc(householdId).get();
    if (!doc.exists) return null;
    return (doc.data() as Map<String, dynamic>)['inviteCode'] as String?;
  }
}
