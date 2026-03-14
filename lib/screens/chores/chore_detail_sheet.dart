import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/chore.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';

final _fmt = DateFormat('EEE, MMM d yyyy');
final _dateFmt = DateFormat('MMM d, yyyy');

/// Bottom sheet showing full details for a chore.
Future<void> showChoreDetail(
  BuildContext context, {
  required Chore chore,
  required String householdId,
  String? currentUid,
  bool isOwner = false,
}) async {
  UserModel? assignee;
  List<(UserModel, dynamic)> allMembers = [];
  if (chore.assignedToId != null || isOwner || currentUid != null) {
    try {
      allMembers = await FirestoreService().getHouseholdMembers(householdId);
      assignee = allMembers
          .where((m) => m.$1.uid == chore.assignedToId)
          .map((m) => m.$1)
          .firstOrNull;
    } catch (_) {}
  }

  if (!context.mounted) return;

  final canEdit = isOwner || chore.createdById == currentUid;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _ChoreDetailSheet(
      chore: chore,
      assignee: assignee,
      allMembers: allMembers,
      householdId: householdId,
      currentUid: currentUid,
      canEdit: canEdit,
    ),
  );
}

class _ChoreDetailSheet extends StatelessWidget {
  final Chore chore;
  final UserModel? assignee;
  final List<(UserModel, dynamic)> allMembers;
  final String householdId;
  final String? currentUid;
  final bool canEdit;

  const _ChoreDetailSheet({
    required this.chore,
    required this.allMembers,
    required this.householdId,
    this.assignee,
    this.currentUid,
    this.canEdit = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title + status + edit button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  chore.title,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    decoration:
                        chore.isCompleted ? TextDecoration.lineThrough : null,
                    color:
                        chore.isCompleted ? colors.onSurfaceVariant : null,
                  ),
                ),
              ),
              if (chore.isRepeatable)
                Chip(
                  label: const Text('🔁 Repeatable'),
                  backgroundColor: colors.primaryContainer,
                  labelStyle: TextStyle(color: colors.onPrimaryContainer),
                )
              else
                Chip(
                  label: Text(chore.isCompleted ? '✅ Done' : '⏳ Pending'),
                  backgroundColor: chore.isCompleted
                      ? colors.secondaryContainer
                      : colors.tertiaryContainer,
                  labelStyle: TextStyle(
                    color: chore.isCompleted
                        ? colors.onSecondaryContainer
                        : colors.onTertiaryContainer,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // XP
          _DetailRow(
            icon: Icons.star_outlined,
            label: 'XP Reward',
            value: '${chore.xpReward} XP',
          ),
          const SizedBox(height: 12),

          // Assignee
          _DetailRow(
            icon: Icons.person_outline,
            label: 'Assigned to',
            value: chore.isRepeatable
                ? 'Open to all 🆓'
                : (assignee?.displayName ?? '🆓 Up for grabs'),
          ),
          const SizedBox(height: 12),

          // Frequency
          _DetailRow(
            icon: Icons.repeat,
            label: 'Frequency',
            value: chore.frequency.label,
          ),

          // Due date
          if (chore.dueDate != null) ...[
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: 'Due',
              value: _fmt.format(chore.dueDate!),
            ),
          ],

          // Completed at
          if (chore.completedAt != null) ...[
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.check_circle_outline,
              label: 'Completed',
              value: _fmt.format(chore.completedAt!),
            ),
          ],

          // Description
          if (chore.description != null && chore.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Notes', style: textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(chore.description!, style: textTheme.bodyMedium),
          ],

          // Edit + Delete actions for owner/creator
          if (canEdit) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showEditChoreSheet(
                        context,
                        chore: chore,
                        allMembers: allMembers,
                        householdId: householdId,
                        currentUid: currentUid,
                      );
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
                      side: BorderSide(color: colors.error),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Delete chore?'),
                          content: const Text(
                              'This will permanently remove this chore.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: colors.error),
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await FirestoreService()
                            .deleteChore(householdId, chore.id);
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Edit chore sheet ─────────────────────────────────────────────────────────

Future<void> _showEditChoreSheet(
  BuildContext context, {
  required Chore chore,
  required List<(UserModel, dynamic)> allMembers,
  required String householdId,
  String? currentUid,
}) async {
  final service = FirestoreService();
  final titleCtrl = TextEditingController(text: chore.title);
  final descCtrl = TextEditingController(text: chore.description ?? '');
  ChoreFrequency selectedFrequency = chore.frequency;
  DateTime? dueDate = chore.dueDate;
  int xpReward = chore.xpReward;
  String assignedTo = chore.assignedToId ?? '';

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
            Text('Edit Chore', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: assignedTo.isEmpty ? null : assignedTo,
              decoration: const InputDecoration(
                  labelText: 'Assign to', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(
                    value: '', child: Text('🆓 Up for grabs')),
                ...allMembers.map((m) => DropdownMenuItem(
                    value: m.$1.uid,
                    child: Text(m.$1.uid == currentUid
                        ? 'Me (${m.$1.displayName})'
                        : m.$1.displayName))),
              ],
              onChanged: (v) => setS(() => assignedTo = v ?? ''),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ChoreFrequency>(
              value: selectedFrequency,
              decoration: const InputDecoration(
                  labelText: 'Frequency', border: OutlineInputBorder()),
              items: ChoreFrequency.values
                  .map((f) => DropdownMenuItem(
                      value: f, child: Text(f.label)))
                  .toList(),
              onChanged: (v) => setS(() => selectedFrequency = v!),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: dueDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setS(() => dueDate = picked);
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(dueDate == null
                  ? 'Pick due date (optional)'
                  : 'Due: ${_dateFmt.format(dueDate!)}'),
            ),
            const SizedBox(height: 12),
            Text('⭐ $xpReward XP',
                style: Theme.of(ctx).textTheme.bodyMedium),
            Slider(
              value: xpReward.toDouble(),
              min: 10,
              max: 500,
              divisions: 49,
              label: '$xpReward XP',
              onChanged: (v) => setS(() => xpReward = v.round()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                await service.updateChore(householdId, chore.id, {
                  'title': title,
                  'description': descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  'assignedToId':
                      assignedTo.isEmpty ? null : assignedTo,
                  'frequency': selectedFrequency.name,
                  'dueDate': dueDate != null
                      ? dueDate!.millisecondsSinceEpoch
                      : null,
                  'xpReward': xpReward,
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── Helper widget ────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: colors.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        Expanded(
          child: Text(value, style: textTheme.bodyMedium),
        ),
      ],
    );
  }
}
