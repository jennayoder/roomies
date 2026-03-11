import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/chore.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';

final _fmt = DateFormat('EEE, MMM d yyyy');

/// Bottom sheet showing full details for a chore.
Future<void> showChoreDetail(
  BuildContext context, {
  required Chore chore,
  required String householdId,
}) async {
  // Fetch assignee name
  UserModel? assignee;
  if (chore.assignedToId != null) {
    try {
      final members = await FirestoreService().getHouseholdMembers(householdId);
      assignee = members
          .where((m) => m.$1.uid == chore.assignedToId)
          .map((m) => m.$1)
          .firstOrNull;
    } catch (_) {}
  }

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _ChoreDetailSheet(chore: chore, assignee: assignee),
  );
}

class _ChoreDetailSheet extends StatelessWidget {
  final Chore chore;
  final UserModel? assignee;
  const _ChoreDetailSheet({required this.chore, this.assignee});

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

          // Title + status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  chore.title,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    decoration: chore.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: chore.isCompleted
                        ? colors.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Chip(
                label: Text(
                  chore.isCompleted ? '✅ Done' : '⏳ Pending',
                  style: TextStyle(
                    color: chore.isCompleted
                        ? colors.onSecondaryContainer
                        : colors.onTertiaryContainer,
                  ),
                ),
                backgroundColor: chore.isCompleted
                    ? colors.secondaryContainer
                    : colors.tertiaryContainer,
              ),
            ],
          ),

          if (chore.description != null) ...[
            const SizedBox(height: 8),
            Text(
              chore.description!,
              style: textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          _DetailRow(
            icon: Icons.star,
            label: 'XP Reward',
            value: '⭐ ${chore.xpReward} XP',
            valueColor: colors.primary,
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.person_outlined,
            label: 'Assigned to',
            value: chore.assignedToId == null
                ? '🆓 Up for grabs'
                : (assignee?.displayName ?? 'Loading…'),
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.repeat,
            label: 'Frequency',
            value: chore.frequency.label,
          ),
          if (chore.dueDate != null) ...[
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.calendar_today,
              label: 'Due date',
              value: _fmt.format(chore.dueDate!),
              valueColor: chore.dueDate!.isBefore(DateTime.now()) && !chore.isCompleted
                  ? colors.error
                  : null,
            ),
          ],
          if (chore.isCompleted && chore.completedAt != null) ...[
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.check_circle_outline,
              label: 'Completed on',
              value: _fmt.format(chore.completedAt!),
              valueColor: colors.secondary,
            ),
          ],
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.schedule,
            label: 'Created',
            value: _fmt.format(chore.createdAt),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
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
          '$label:',
          style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
