import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/household.dart';
import '../models/user_model.dart';

/// Handles creating, joining, and managing households.
///
/// All household data (and its sub-collections) lives under
/// /households/{householdId}/.
class HouseholdService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  // ─── Create ────────────────────────────────────────────────────────────────

  /// Creates a new household and sets the caller as the owner.
  Future<Household> createHousehold(String name) async {
    final inviteCode = _generateInviteCode();
    final now = DateTime.now();

    final ref = _db.collection('households').doc();
    final household = Household(
      id: ref.id,
      name: name,
      ownerId: _uid,
      members: {_uid: HouseholdRole.owner},
      inviteCode: inviteCode,
      createdAt: now,
    );

    final batch = _db.batch();
    batch.set(ref, household.toMap());
    batch.update(_db.collection('users').doc(_uid), {
      'householdId': ref.id,
    });
    await batch.commit();

    return household;
  }

  // ─── Join ──────────────────────────────────────────────────────────────────

  /// Looks up a household by [inviteCode] and adds the caller as a guest.
  ///
  /// Throws a [StateError] if no household is found or the user is already
  /// a member.
  Future<Household> joinHousehold(String inviteCode) async {
    final query = await _db
        .collection('households')
        .where('inviteCode', isEqualTo: inviteCode.toUpperCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw StateError('No household found for invite code "$inviteCode".');
    }

    final doc = query.docs.first;
    final household = Household.fromDoc(doc);

    if (household.members.containsKey(_uid)) {
      throw StateError('You are already a member of this household.');
    }

    final batch = _db.batch();
    batch.update(doc.reference, {
      'members.$_uid': HouseholdRole.guest.name,
      'memberIds': FieldValue.arrayUnion([_uid]),
    });
    batch.update(_db.collection('users').doc(_uid), {
      'householdId': household.id,
    });
    await batch.commit();

    return household.copyWith(
      members: {...household.members, _uid: HouseholdRole.guest},
    );
  }

  // ─── Leave ─────────────────────────────────────────────────────────────────

  /// Removes the caller from a household.
  ///
  /// If the caller is the last member, the household document is deleted.
  Future<void> leaveHousehold(String householdId) async {
    final ref = _db.collection('households').doc(householdId);
    final doc = await ref.get();
    final household = Household.fromDoc(doc);

    final batch = _db.batch();

    if (household.memberIds.length <= 1) {
      batch.delete(ref);
    } else {
      batch.update(ref, {
        'members.$_uid': FieldValue.delete(),
        'memberIds': FieldValue.arrayRemove([_uid]),
      });
    }

    batch.update(_db.collection('users').doc(_uid), {
      'householdId': FieldValue.delete(),
    });

    await batch.commit();
  }

  // ─── Role management ───────────────────────────────────────────────────────

  /// Updates the role of [uid] in [householdId]. Only the owner should call
  /// this; enforce in UI.
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

  // ─── Fetch ─────────────────────────────────────────────────────────────────

  /// Returns a real-time stream of the household document.
  Stream<Household?> householdStream(String householdId) {
    return _db
        .collection('households')
        .doc(householdId)
        .snapshots()
        .map((doc) => doc.exists ? Household.fromDoc(doc) : null);
  }

  /// Fetches all [UserModel] profiles for the given UIDs.
  Future<List<UserModel>> fetchMembers(List<String> memberIds) async {
    if (memberIds.isEmpty) return [];
    final snapshots = await Future.wait(
      memberIds.map((uid) => _db.collection('users').doc(uid).get()),
    );
    return snapshots
        .where((doc) => doc.exists)
        .map(UserModel.fromDoc)
        .toList();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Generates a random 6-character uppercase alphanumeric invite code.
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
