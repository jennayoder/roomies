import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/chore.dart';
import '../../models/chore_completion.dart';
import '../../models/household.dart';
import '../../models/personal_task.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/household_service.dart';
import '../../services/personal_task_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import 'chore_detail_sheet.dart';

final _dateFmt = DateFormat.yMMMd();

/// Unified Chores screen — all chores have XP, assignable to anyone.
class ChoresScreen extends StatefulWidget {
  const ChoresScreen({super.key});

  @override
  State<ChoresScreen> createState() => _ChoresScreenState();
}

class _ChoresScreenState extends State<ChoresScreen> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return StreamBuilder<UserModel?>(
      stream: auth.userProfileStream(),
      builder: (context, snap) {
        final user = snap.data;
        if (user?.householdId == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chores')),
            body: const EmptyState(
              icon: Icons.checklist_outlined,
              title: 'No household',
              subtitle: 'Join or create a household from the Home tab.',
            ),
          );
        }

        final householdId = user!.householdId!;
        final uid = auth.currentUser!.uid;

        return StreamBuilder<Household?>(
          stream: HouseholdService().householdStream(householdId),
          builder: (context, householdSnap) {
            final role = householdSnap.data?.members[uid];
            final isOwner = role == HouseholdRole.owner;
            final isGuest = role == HouseholdRole.guest;

            return Scaffold(
              appBar: AppBar(
                title: const Text('Chores'),
                actions: [
                  TextButton.icon(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    icon: Icon(_showAll ? Icons.person : Icons.people),
                    label: Text(_showAll ? 'Mine' : 'All'),
                  ),
                ],
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _showAddChoreSheet(
                  context,
                  householdId: householdId,
                  currentUid: uid,
                  isOwner: isOwner,
                  household: householdSnap.data,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Chore'),
              ),
              body: _CombinedChoresList(
                householdId: householdId,
                currentUid: uid,
                isOwner: isOwner,
                showAll: _showAll || isOwner || isGuest,
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Combined list ────────────────────────────────────────────────────────────

class _CombinedChoresList extends StatelessWidget {
  final String householdId;
  final String currentUid;
  final bool isOwner;
  final bool showAll;

  const _CombinedChoresList({
    required this.householdId,
    required this.currentUid,
    required this.isOwner,
    this.showAll = false,
  });

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();
    final taskService = PersonalTaskService();
    final taskStream = isOwner
        ? taskService.getAllTasks(householdId)
        : taskService.getTasksForUser(householdId, currentUid);

    return StreamBuilder<List<Chore>>(
      stream: firestoreService.choresStream(householdId),
      builder: (context, choreSnap) {
        return StreamBuilder<List<PersonalTask>>(
          stream: taskStream,
          builder: (context, taskSnap) {
            if (choreSnap.connectionState == ConnectionState.waiting &&
                taskSnap.connectionState == ConnectionState.waiting) {
              return const LoadingWidget(message: 'Loading chores…');
            }

            final allChores = choreSnap.data ?? [];
            final tasks = taskSnap.data ?? [];

            // Filter chores by assignee unless showAll
            final chores = showAll
                ? allChores
                : allChores
                    .where((c) =>
                        c.assignedToId == null ||
                        c.assignedToId == currentUid)
                    .toList();

            if (chores.isEmpty && tasks.isEmpty) {
              return EmptyState(
                icon: Icons.checklist_outlined,
                title: showAll ? 'No chores yet' : 'No chores assigned to you',
                subtitle: showAll
                    ? 'Tap "Add Chore" to get started.'
                    : 'Tap "All" to see everyone\'s chores.',
              );
            }

            final pendingChores = chores.where((c) => !c.isCompleted).toList();
            final doneChores = chores.where((c) => c.isCompleted).toList();
            final needsApproval = tasks
                .where((t) =>
                    t.isComplete &&
                    t.requiresApproval &&
                    t.approvedBy == null)
                .toList();
            final pendingTasks = tasks.where((t) => !t.isComplete).toList();
            final doneTasks = tasks
                .where((t) =>
                    t.isComplete &&
                    (!t.requiresApproval || t.approvedBy != null))
                .toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (needsApproval.isNotEmpty && isOwner) ...[
                  _sectionHeader(context, '⏳ Awaiting Approval'),
                  const SizedBox(height: 8),
                  ...needsApproval.map((t) => _TaskCard(
                        task: t,
                        householdId: householdId,
                        currentUid: currentUid,
                        isOwner: isOwner,
                        service: taskService,
                      )),
                  const SizedBox(height: 16),
                ],
                if (pendingTasks.isNotEmpty) ...[
                  _sectionHeader(context, '⭐ XP Chores'),
                  const SizedBox(height: 8),
                  ...pendingTasks.map((t) => _TaskCard(
                        task: t,
                        householdId: householdId,
                        currentUid: currentUid,
                        isOwner: isOwner,
                        service: taskService,
                      )),
                  const SizedBox(height: 16),
                ],
                if (pendingChores.isNotEmpty) ...[
                  _sectionHeader(context, 'To Do'),
                  const SizedBox(height: 8),
                  ...pendingChores.map((c) => _ChoreCard(
                        chore: c,
                        householdId: householdId,
                        currentUid: currentUid,
                        service: firestoreService,
                      )),
                ],
                if (doneChores.isNotEmpty || doneTasks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionHeader(context, 'Done'),
                  const SizedBox(height: 8),
                  ...doneTasks.map((t) => _TaskCard(
                        task: t,
                        householdId: householdId,
                        currentUid: currentUid,
                        isOwner: isOwner,
                        service: taskService,
                      )),
                  ...doneChores.map((c) => _ChoreCard(
                        chore: c,
                        householdId: householdId,
                        currentUid: currentUid,
                        service: firestoreService,
                      )),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

// ─── Chores list (no Scaffold) ────────────────────────────────────────────────

class _ChoresList extends StatelessWidget {
  final String householdId;
  final String currentUid;

  const _ChoresList({required this.householdId, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();

    return StreamBuilder<List<Chore>>(
      stream: service.choresStream(householdId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingWidget(message: 'Loading chores…');
        }

        final chores = snapshot.data ?? [];
        if (chores.isEmpty) {
          return const EmptyState(
            icon: Icons.checklist_outlined,
            title: 'No chores yet',
            subtitle: 'Tap "Add Chore" to assign a task.',
          );
        }

        final pending = chores.where((c) => !c.isCompleted).toList();
        final done = chores.where((c) => c.isCompleted).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (pending.isNotEmpty) ...[
              _sectionHeader(context, 'To do'),
              const SizedBox(height: 8),
              ...pending.map((c) => _ChoreCard(
                    chore: c,
                    householdId: householdId,
                    currentUid: currentUid,
                    service: service,
                  )),
            ],
            if (done.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionHeader(context, 'Done'),
              const SizedBox(height: 8),
              ...done.map((c) => _ChoreCard(
                    chore: c,
                    householdId: householdId,
                    currentUid: currentUid,
                    service: service,
                  )),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

// ─── Tasks list (no Scaffold) ─────────────────────────────────────────────────

class _TasksList extends StatelessWidget {
  final String householdId;
  final String currentUid;
  final bool isOwner;

  const _TasksList({
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

    return StreamBuilder<List<PersonalTask>>(
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
}

// ─── Chore card ───────────────────────────────────────────────────────────────

class _ChoreCard extends StatelessWidget {
  final Chore chore;
  final String householdId;
  final String currentUid;
  final FirestoreService service;

  const _ChoreCard({
    required this.chore,
    required this.householdId,
    required this.currentUid,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    if (chore.isRepeatable) {
      return _RepeatableChoreCard(
        chore: chore,
        householdId: householdId,
        currentUid: currentUid,
        service: service,
      );
    }

    final colors = Theme.of(context).colorScheme;
    final isUnassigned = chore.assignedToId == null;
    final isAssignedToMe = chore.assignedToId == currentUid;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isUnassigned ? colors.tertiaryContainer.withOpacity(0.3) : null,
      child: ListTile(
        onTap: () => showChoreDetail(context, chore: chore, householdId: householdId),
        leading: isUnassigned
            ? IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Claim this chore',
                onPressed: () => service.claimChore(householdId, chore.id, currentUid),
              )
            : Checkbox(
                value: chore.isCompleted,
                onChanged: isAssignedToMe || true
                    ? (v) => service.toggleChoreComplete(householdId, chore.id, v ?? false)
                    : null,
              ),
        title: Text(
          chore.title,
          style: chore.isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          [
            '⭐ ${chore.xpReward} XP',
            if (isUnassigned) '🆓 Up for grabs',
            chore.frequency.label,
            if (chore.dueDate != null) 'Due ${_dateFmt.format(chore.dueDate!)}',
            if (chore.description != null) chore.description!,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isUnassigned
            ? FilledButton.tonal(
                onPressed: () => service.claimChore(householdId, chore.id, currentUid),
                child: const Text('Claim'),
              )
            : IconButton(
                icon: Icon(Icons.delete_outlined, color: colors.error),
                onPressed: () => service.deleteChore(householdId, chore.id),
              ),
      ),
    );
  }
}

// ─── Repeatable chore card ────────────────────────────────────────────────────

class _RepeatableChoreCard extends StatelessWidget {
  final Chore chore;
  final String householdId;
  final String currentUid;
  final FirestoreService service;

  const _RepeatableChoreCard({
    required this.chore,
    required this.householdId,
    required this.currentUid,
    required this.service,
  });

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: () => showChoreDetail(context, chore: chore, householdId: householdId),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.repeat, color: colors.onPrimaryContainer, size: 20),
            ),
            title: Text(chore.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '⭐ ${chore.xpReward} XP · Always available',
              style: textTheme.bodySmall,
            ),
            trailing: FilledButton(
              onPressed: () async {
                // Get current user's display name
                final user = await FirestoreService()
                    .getHouseholdMembers(householdId)
                    .then((members) =>
                        members.where((m) => m.$1.uid == currentUid).firstOrNull);
                final name = user?.$1.displayName ?? 'Someone';
                await service.claimRepeatableChore(
                  householdId,
                  chore.id,
                  currentUid,
                  name,
                  xpReward: chore.xpReward,
                  choreTitle: chore.title,
                );
              },
              child: const Text('Claim +XP'),
            ),
          ),

          // Today's completions only — resets at midnight
          StreamBuilder<List<ChoreCompletion>>(
            stream: service.choreCompletionsStream(householdId, chore.id),
            builder: (context, snap) {
              final now = DateTime.now();
              final startOfDay = DateTime(now.year, now.month, now.day);
              final todayOnly = (snap.data ?? [])
                  .where((c) => c.claimedAt.isAfter(startOfDay))
                  .toList();

              if (todayOnly.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text('No claims today — be the first!',
                      style: textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant)),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: todayOnly.take(10).map((c) {
                    return Chip(
                      avatar: const Icon(Icons.check_circle, size: 14),
                      label: Text(
                        '${c.displayName} · ${_timeAgo(c.claimedAt)}',
                        style: textTheme.labelSmall,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: colors.secondaryContainer,
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Task card ────────────────────────────────────────────────────────────────

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

// ─── Add chore sheet ──────────────────────────────────────────────────────────

Future<void> _showAddChoreSheet(
  BuildContext context, {
  required String householdId,
  required String currentUid,
  required bool isOwner,
  Household? household,
}) async {
  final service = FirestoreService();

  // Fetch all members for assignee picker
  // Owner can assign to anyone (including themselves)
  // Everyone else can assign to anyone EXCEPT themselves
  List<(String uid, String name)> members = [];
  try {
    final fetched = await FirestoreService().getHouseholdMembers(householdId);
    members = fetched
        .where((m) => isOwner || m.$1.uid != currentUid) // non-owners can't self-assign
        .map((m) => (m.$1.uid, m.$1.uid == currentUid ? 'Me (${m.$1.displayName})' : m.$1.displayName))
        .toList();
  } catch (_) {
    // fallback: owner can assign to self, others get no options
    if (isOwner) members = [(currentUid, 'Me')];
  }

  if (!context.mounted) return;

  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  ChoreFrequency selectedFrequency = ChoreFrequency.once;
  DateTime? dueDate;
  int xpReward = 25;
  bool isRepeatable = false;
  // Non-owners default to unassigned (they can't self-assign)
  String assignedTo = isOwner ? currentUid : '';

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
            Text('Add Chore', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Chore title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              textCapitalization: TextCapitalization.sentences,
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
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('🆓 Up for grabs (unassigned)'),
                ),
                ...members.map((m) => DropdownMenuItem(value: m.$1, child: Text(m.$2))),
              ],
              onChanged: (v) => setS(() => assignedTo = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ChoreFrequency>(
              value: selectedFrequency,
              decoration: const InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(),
              ),
              items: ChoreFrequency.values
                  .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                  .toList(),
              onChanged: (v) => setS(() => selectedFrequency = v!),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setS(() => dueDate = picked);
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(
                dueDate == null
                    ? 'Pick due date (optional)'
                    : 'Due: ${_dateFmt.format(dueDate!)}',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('XP Reward', style: Theme.of(ctx).textTheme.bodyMedium),
                Text(
                  '⭐ $xpReward XP',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            Slider(
              value: xpReward.toDouble(),
              min: 10,
              max: 500,
              divisions: 49,
              label: '$xpReward XP',
              onChanged: (v) => setS(() => xpReward = v.round()),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: isRepeatable,
              title: const Text('🔁 Always available'),
              subtitle: Text(
                isRepeatable
                    ? 'Anyone can claim this chore repeatedly — it never disappears'
                    : 'One-time chore — disappears when completed',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              onChanged: (v) => setS(() => isRepeatable = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                final chore = Chore(
                  id: const Uuid().v4(),
                  title: title,
                  description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  assignedToId: isRepeatable ? null : (assignedTo.isEmpty ? null : assignedTo),
                  frequency: selectedFrequency,
                  dueDate: isRepeatable ? null : dueDate,
                  createdAt: DateTime.now(),
                  xpReward: xpReward,
                  isRepeatable: isRepeatable,
                );
                await service.addChore(householdId, chore);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── Assign task sheet ────────────────────────────────────────────────────────

Future<void> _showAssignTaskSheet(
  BuildContext context, {
  required String householdId,
  required String currentUid,
}) async {
  final service = PersonalTaskService();
  final members = await FirestoreService().getHouseholdMembers(householdId);
  if (!context.mounted) return;

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
              'Assign XP Chore',
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
                Text('XP Reward', style: Theme.of(ctx).textTheme.bodyMedium),
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
