import 'package:cloud_firestore/cloud_firestore.dart';

/// A household-owner-assigned task with an XP reward for the assignee.
///
/// Stored at /households/{id}/personalTasks/{taskId}.
class PersonalTask {
  final String id;
  final String title;
  final String? description;

  /// UID of the household member this task is assigned to.
  final String assignedTo;

  /// UID of the person who created this task (usually the owner).
  final String assignedBy;

  /// XP awarded when the task is approved (50–1000).
  final int xpReward;

  final bool isComplete;

  /// Whether the task requires owner approval before XP is awarded.
  final bool requiresApproval;

  /// UID of whoever approved the task (null until approved).
  final String? approvedBy;

  final DateTime createdAt;
  final DateTime? completedAt;

  const PersonalTask({
    required this.id,
    required this.title,
    this.description,
    required this.assignedTo,
    required this.assignedBy,
    required this.xpReward,
    this.isComplete = false,
    this.requiresApproval = true,
    this.approvedBy,
    required this.createdAt,
    this.completedAt,
  });

  factory PersonalTask.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PersonalTask(
      id: doc.id,
      title: data['title'] as String,
      description: data['description'] as String?,
      assignedTo: data['assignedTo'] as String,
      assignedBy: data['assignedBy'] as String,
      xpReward: (data['xpReward'] as int?) ?? 50,
      isComplete: (data['isComplete'] as bool?) ?? false,
      requiresApproval: (data['requiresApproval'] as bool?) ?? true,
      approvedBy: data['approvedBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'description': description,
        'assignedTo': assignedTo,
        'assignedBy': assignedBy,
        'xpReward': xpReward,
        'isComplete': isComplete,
        'requiresApproval': requiresApproval,
        'approvedBy': approvedBy,
        'createdAt': Timestamp.fromDate(createdAt),
        'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      };

  PersonalTask copyWith({
    bool? isComplete,
    String? approvedBy,
    DateTime? completedAt,
  }) =>
      PersonalTask(
        id: id,
        title: title,
        description: description,
        assignedTo: assignedTo,
        assignedBy: assignedBy,
        xpReward: xpReward,
        isComplete: isComplete ?? this.isComplete,
        requiresApproval: requiresApproval,
        approvedBy: approvedBy ?? this.approvedBy,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );
}
