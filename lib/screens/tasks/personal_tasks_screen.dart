import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/household.dart';
import '../../models/personal_task.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/household_service.dart';
import '../../services/personal_task_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

/// Tasks tab — household owner assigns personal tasks with XP rewards;
/// members see their own tasks and can mark them complete.
class PersonalTasksScreen extends StatelessWidget {
  const PersonalTasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return StreamBuilder<UserModel?>(
      stream: auth.userProfileStream(),
      builder: (context, snap) {
        final householdId = snap.data?.householdId;
        if (householdId == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Tasks')),
            body: const EmptyState(
              icon: Icons.task_alt_outlined,
              title: 'No household',
              subtitle: 'Join or create a household from the Home tab.',
            ),
          );
        }

        return StreamBuilder<Household?>(
          stream: HouseholdService().householdStream(householdId),
          builder: (context, householdSnap) {
            if (householdSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: LoadingWidget(message: 'Loading tasks…'),
              );
            }
            final uid = auth.currentUser!.uid;
            final role = householdSnap.data?.members[uid];
            final isOwner = role == HouseholdRole.owner;

            return _TasksContent(
              householdId: householdId,
              currentUid: uid,
              isOwner: isOwner,
            );
          },
        );
      },
    );
  }
}

class _TasksContent extends StatelessWidget {
  final String householdId;
  final String currentUid;
  final bool isOwner;

  const _TasksContent({
    required this.householdId,
    required this.currentUid,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context) {
    final service = PersonalTaskService();
    final stream = isOwner
        ? service.getAllTasks(householdId)
        : service.getTasksForUser(householdId, currentUid);

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateTaskSheet(context, service),
              icon: const Icon(Icons.add),
              label: const Text('Assign Task'),
            )
          : null,
      body: StreamBuilder<List<PersonalTask>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget(message: 'Loading tasks…');
          }

          final tasks = snapshot.data ?? [];
          if (tasks.isEmpty) {
            return EmptyState(
              icon: Icons.task_alt_outlined,
              title: isOwner ? 'No tasks assigned' : 'No tasks for you',
              subtitle: isOwner
                  ? 'Tap "Assign Task" to give a member a task.'
                  : "Your owner hasn't assigned any tasks yet.",
            );
          }

          final needsApproval = tasks
              .where((t) =>
                  t.isComplete && t.requiresApproval && t.approvedBy == null)
              .toList();
          final pending = tasks.where((t) => !t.isComplete).toList();
          final done = tasks
              .where((t) =>
                  t.isComplete &&
                  (!t.requiresApproval || t.approvedBy != null))
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (needsApproval.isNotEmpty && isOwner) ...[
                _sectionHeader(context, 'Awaiting Approval'),
                const SizedBox(height: 8),
                ...needsApproval.map((t) => _TaskCard(
                      task: t,
                      householdId: householdId,
                      currentUid: currentUid,
                      isOwner: isOwner,
                      service: service,
                    )),
                const SizedBox(height: 16),
              ],
              if (pending.isNotEmpty) ...[
                _sectionHeader(context, 'Pending'),
                const SizedBox(height: 8),
                ...pending.map((t) => _TaskCard(
                      task: t,
                      householdId: householdId,
                      currentUid: currentUid,
                      isOwner: isOwner,
                      service: service,
                    )),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionHeader(context, 'Completed'),
                const SizedBox(height: 8),
                ...done.map((t) => _TaskCard(
                      task: t,
                      householdId: householdId,
                      currentUid: currentUid,
                      isOwner: isOwner,
                      service: service,
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  Future<void> _showCreateTaskSheet(
    BuildContext context,
    PersonalTaskService service,
  ) async {
    final members =
        await FirestoreService().getHouseholdMembers(householdId);
    if (!context.mounted) return;

    // Filter out the owner themselves so they don't assign tasks to themselves.
    final assignableMembers =
        members.where((m) => m.$1.uid != currentUid).toList();

    if (assignableMembers.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other members to assign tasks to.')),
        );
      }
      return;
    }

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    int xpReward = 100;
    bool requiresApproval = true;
    String assignedTo = assignableMembers.first.$1.uid;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Assign Task',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Task title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: assignedTo,
                decoration: const InputDecoration(
                  labelText: 'Assign to',
                  border: OutlineInputBorder(),
                ),
                items: assignableMembers
                    .map((m) => DropdownMenuItem(
                          value: m.$1.uid,
                          child: Text(m.$1.displayName),
                        ))
                    .toList(),
                onChanged: (v) => setS(() => assignedTo = v!),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'XP Reward',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  Text(
                    '$xpReward XP',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              Slider(
                value: xpReward.toDouble(),
                min: 50,
                max: 1000,
                divisions: 19,
                label: '$xpReward XP',
                onChanged: (v) => setS(() => xpReward = v.round()),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: requiresApproval,
                title: const Text('Requires your approval'),
                subtitle: const Text('XP held until you approve completion'),
                onChanged: (v) => setS(() => requiresApproval = v ?? true),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) return;

                  final task = PersonalTask(
                    id: const Uuid().v4(),
                    title: title,
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    assignedTo: assignedTo,
                    assignedBy: currentUid,
                    xpReward: xpReward,
                    requiresApproval: requiresApproval,
                    createdAt: DateTime.now(),
                  );
                  await service.createTask(householdId, task);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Assign'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final PersonalTask task;
  final String householdId;
  final String currentUid;
  final bool isOwner;
  final PersonalTaskService service;

  const _TaskCard({
    required this.task,
    required this.householdId,
    required this.currentUid,
    required this.isOwner,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isAssignedToMe = task.assignedTo == currentUid;
    final awaitingApproval =
        task.isComplete && task.requiresApproval && task.approvedBy == null;
    final isApproved =
        task.isComplete && (!task.requiresApproval || task.approvedBy != null);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: isApproved
            ? Icon(Icons.check_circle, color: colors.primary)
            : awaitingApproval
                ? Icon(Icons.pending_outlined, color: colors.tertiary)
                : isAssignedToMe && !isOwner
                    ? Checkbox(
                        value: task.isComplete,
                        onChanged: task.isComplete
                            ? null
                            : (_) =>
                                service.markComplete(householdId, task.id),
                      )
                    : Icon(
                        Icons.radio_button_unchecked,
                        color: colors.onSurfaceVariant,
                      ),
        title: Text(
          task.title,
          style: isApproved
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          [
            '${task.xpReward} XP',
            if (task.description != null) task.description!,
            if (awaitingApproval) '⏳ Awaiting approval',
          ].join(' · '),
          style: TextStyle(
            color: awaitingApproval ? colors.tertiary : colors.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        trailing: isOwner
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (awaitingApproval)
                    FilledButton.tonal(
                      onPressed: () =>
                          service.approveTask(householdId, task.id, currentUid),
                      child: const Text('Approve'),
                    ),
                  IconButton(
                    icon: Icon(Icons.delete_outlined, color: colors.error),
                    onPressed: () => service.deleteTask(householdId, task.id),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
