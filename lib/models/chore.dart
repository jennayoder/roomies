import 'package:cloud_firestore/cloud_firestore.dart';

/// How often a chore recurs.
enum ChoreFrequency { once, daily, weekly, biweekly, monthly }

extension ChoreFrequencyLabel on ChoreFrequency {
  String get label => switch (this) {
        ChoreFrequency.once => 'One-time',
        ChoreFrequency.daily => 'Daily',
        ChoreFrequency.weekly => 'Weekly',
        ChoreFrequency.biweekly => 'Bi-weekly',
        ChoreFrequency.monthly => 'Monthly',
      };
}

/// A household chore or task assigned to a member.
///
/// Stored at: /households/{householdId}/chores/{choreId}
class Chore {
  final String id;
  final String title;
  final String? description;

  /// UID of the member responsible for this chore.
  final String? assignedToId;

  final ChoreFrequency frequency;
  final DateTime? dueDate;
  final bool isCompleted;

  /// When this chore was last marked as completed.
  final DateTime? completedAt;

  final DateTime createdAt;

  const Chore({
    required this.id,
    required this.title,
    this.description,
    this.assignedToId,
    this.frequency = ChoreFrequency.once,
    this.dueDate,
    this.isCompleted = false,
    this.completedAt,
    required this.createdAt,
  });

  // ─── Firestore serialization ───────────────────────────────────────────────

  factory Chore.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Chore(
      id: doc.id,
      title: data['title'] as String,
      description: data['description'] as String?,
      assignedToId: data['assignedToId'] as String?,
      frequency: ChoreFrequency.values.firstWhere(
        (f) => f.name == data['frequency'],
        orElse: () => ChoreFrequency.once,
      ),
      dueDate: data['dueDate'] != null
          ? (data['dueDate'] as Timestamp).toDate()
          : null,
      isCompleted: (data['isCompleted'] as bool?) ?? false,
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'description': description,
        'assignedToId': assignedToId,
        'frequency': frequency.name,
        'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
        'isCompleted': isCompleted,
        'completedAt':
            completedAt != null ? Timestamp.fromDate(completedAt!) : null,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  Chore copyWith({
    bool? isCompleted,
    DateTime? completedAt,
    String? assignedToId,
  }) =>
      Chore(
        id: id,
        title: title,
        description: description,
        assignedToId: assignedToId ?? this.assignedToId,
        frequency: frequency,
        dueDate: dueDate,
        isCompleted: isCompleted ?? this.isCompleted,
        completedAt: completedAt ?? this.completedAt,
        createdAt: createdAt,
      );
}
