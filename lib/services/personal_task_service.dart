import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/personal_task.dart';
import 'xp_service.dart';

/// CRUD operations for household personal tasks.
///
/// Sub-collection path: /households/{id}/personalTasks/{taskId}
class PersonalTaskService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final XpService _xp = XpService();

  CollectionReference _tasks(String householdId) => _db
      .collection('households')
      .doc(householdId)
      .collection('personalTasks');

  /// Creates a new task (owner only).
  Future<void> createTask(String householdId, PersonalTask task) async {
    await _tasks(householdId).doc(task.id).set(task.toMap());
  }

  /// Assignee marks the task as complete. XP is held until approved (if required).
  Future<void> markComplete(String householdId, String taskId) async {
    final doc = await _tasks(householdId).doc(taskId).get();
    if (!doc.exists) return;
    final task = PersonalTask.fromDoc(doc);

    await _tasks(householdId).doc(taskId).update({
      'isComplete': true,
      'completedAt': Timestamp.now(),
    });

    // If no approval needed, award XP immediately.
    if (!task.requiresApproval) {
      await _xp.awardPersonalTaskCompleted(
        task.assignedTo,
        householdId,
        task.xpReward,
      );
    }
  }

  /// Owner approves the task → triggers XP award to the assignee.
  Future<void> approveTask(
    String householdId,
    String taskId,
    String approverUid,
  ) async {
    final doc = await _tasks(householdId).doc(taskId).get();
    if (!doc.exists) return;
    final task = PersonalTask.fromDoc(doc);

    await _tasks(householdId).doc(taskId).update({'approvedBy': approverUid});

    await _xp.awardPersonalTaskCompleted(
      task.assignedTo,
      householdId,
      task.xpReward,
    );
  }

  /// Owner denies the task → resets it back to incomplete so the assignee
  /// can try again (or owner can delete it).
  Future<void> denyTask(String householdId, String taskId) async {
    await _tasks(householdId).doc(taskId).update({
      'isComplete': false,
      'completedAt': null,
      'approvedBy': null,
    });
  }

  /// Stream of tasks assigned to a specific user.
  Stream<List<PersonalTask>> getTasksForUser(String householdId, String uid) {
    return _tasks(householdId)
        .where('assignedTo', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PersonalTask.fromDoc).toList());
  }

  /// Stream of all tasks in the household (owner view).
  Stream<List<PersonalTask>> getAllTasks(String householdId) {
    return _tasks(householdId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PersonalTask.fromDoc).toList());
  }

  Future<void> deleteTask(String householdId, String taskId) async {
    await _tasks(householdId).doc(taskId).delete();
  }
}
