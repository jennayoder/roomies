import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Role enum ────────────────────────────────────────────────────────────────

enum HouseholdRole { owner, renter, princess, guest }

extension HouseholdRoleX on HouseholdRole {
  String get displayName => switch (this) {
        HouseholdRole.owner => 'Owner',
        HouseholdRole.renter => 'Roomie',
        HouseholdRole.princess => 'Princess',
        HouseholdRole.guest => 'Guest',
      };

  String get emoji => switch (this) {
        HouseholdRole.owner => '👑',
        HouseholdRole.renter => '🏠',
        HouseholdRole.princess => '👸',
        HouseholdRole.guest => '🎉',
      };

  String get label => '${emoji} ${displayName}';

  /// Can this role see the Rent tab?
  bool get canSeeRent =>
      this == HouseholdRole.owner || this == HouseholdRole.renter;

  /// Can this role see Expenses and Chores tabs?
  bool get isFullMember => this != HouseholdRole.guest;

  /// Can this role manage other members (change roles, remove)?
  bool get canManageMembers => this == HouseholdRole.owner;
}

// ─── Household model ──────────────────────────────────────────────────────────

/// Represents a shared household in Roomies.
///
/// The [members] map is the source of truth for membership and roles.
/// [memberIds] is derived from [members.keys] for convenience.
class Household {
  final String id;
  final String name;
  final String ownerId;

  /// Maps uid → role for every current member (including the owner).
  final Map<String, HouseholdRole> members;

  /// Short alphanumeric code used to invite new members.
  final String inviteCode;

  final DateTime createdAt;

  const Household({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.members,
    required this.inviteCode,
    required this.createdAt,
  });

  /// All member UIDs (derived from [members]).
  List<String> get memberIds => members.keys.toList();

  // ─── Firestore serialization ───────────────────────────────────────────────

  factory Household.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final ownerId = data['ownerId'] as String;

    // Parse members map (new format); fall back to legacy memberIds list.
    Map<String, HouseholdRole> members;
    final rawMembers = data['members'] as Map<String, dynamic>?;
    if (rawMembers != null && rawMembers.isNotEmpty) {
      members = rawMembers.map(
        (uid, roleStr) => MapEntry(
          uid,
          HouseholdRole.values.firstWhere(
            (r) => r.name == roleStr,
            orElse: () => HouseholdRole.guest,
          ),
        ),
      );
    } else {
      // Legacy: assign owner/renter roles from flat memberIds list.
      final memberIds =
          List<String>.from(data['memberIds'] as List? ?? []);
      members = {
        for (final uid in memberIds)
          uid: uid == ownerId ? HouseholdRole.owner : HouseholdRole.renter,
      };
    }

    return Household(
      id: doc.id,
      name: data['name'] as String,
      ownerId: ownerId,
      members: members,
      inviteCode: data['inviteCode'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'ownerId': ownerId,
        'members': members.map((uid, role) => MapEntry(uid, role.name)),
        'memberIds': memberIds, // kept for Firestore array queries
        'inviteCode': inviteCode,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  Household copyWith({
    String? name,
    Map<String, HouseholdRole>? members,
  }) =>
      Household(
        id: id,
        name: name ?? this.name,
        ownerId: ownerId,
        members: members ?? this.members,
        inviteCode: inviteCode,
        createdAt: createdAt,
      );
}
