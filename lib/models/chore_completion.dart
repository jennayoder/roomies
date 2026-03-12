import 'package:cloud_firestore/cloud_firestore.dart';

/// A single claim/completion of a repeatable chore.
///
/// Stored at: /households/{householdId}/chores/{choreId}/completions/{id}
class ChoreCompletion {
  final String id;
  final String uid;
  final String displayName;
  final DateTime claimedAt;

  const ChoreCompletion({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.claimedAt,
  });

  factory ChoreCompletion.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChoreCompletion(
      id: doc.id,
      uid: data['uid'] as String,
      displayName: data['displayName'] as String? ?? 'Someone',
      claimedAt: (data['claimedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'displayName': displayName,
        'claimedAt': Timestamp.fromDate(claimedAt),
      };
}
