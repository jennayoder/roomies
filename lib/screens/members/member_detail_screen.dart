import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/household.dart';
import '../../models/level_system.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/xp_service.dart';

final _histFmt = DateFormat('MMM d, h:mm a');

/// Displays a member's profile, level, and full XP history.
class MemberDetailScreen extends StatelessWidget {
  final UserModel user;
  final HouseholdRole role;
  final bool isViewerOwner;
  final String? viewerHouseholdId;

  const MemberDetailScreen({
    super.key,
    required this.user,
    required this.role,
    this.isViewerOwner = false,
    this.viewerHouseholdId,
  });

  String _roleLabel(HouseholdRole r) => switch (r) {
        HouseholdRole.owner => '👑 Owner',
        HouseholdRole.renter => '🏠 Roomie',
        HouseholdRole.princess => '👸 Princess',
        HouseholdRole.guest => '🐀 Attic Rat',
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final levelInfo = LevelSystem.infoFor(user.level);
    final avatar = user.currentAvatar ?? levelInfo.avatarEmoji;
    final nextXp = LevelSystem.xpForNextLevel(user.level);
    final prevXp = LevelSystem.xpForNextLevel(user.level - 1) ?? 0;
    final progress = nextXp == null
        ? 1.0
        : (user.totalXp - prevXp) / (nextXp - prevXp);

    return Scaffold(
      appBar: AppBar(
        title: Text(user.displayName),
      ),
      body: Column(
        children: [
          // ── Profile header ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            color: colors.surfaceContainerHighest,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: colors.primaryContainer,
                  child: Text(avatar, style: const TextStyle(fontSize: 36)),
                ),
                const SizedBox(height: 12),
                Text(
                  user.displayName,
                  style: textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _roleLabel(role),
                  style: textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  '${levelInfo.emoji} Level ${user.level} — ${user.title ?? levelInfo.title}',
                  style: textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                // XP progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: colors.surfaceContainerLow,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colors.primary),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  nextXp == null
                      ? '${user.totalXp} XP — Max level!'
                      : '${user.totalXp} / $nextXp XP to Level ${user.level + 1}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // ── XP History ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  '⭐ XP History',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Adjust XP button — owner only, not for themselves
          if (isViewerOwner &&
              role != HouseholdRole.owner &&
              viewerHouseholdId != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () =>
                    _showGrantXpSheet(context, user, viewerHouseholdId!),
                icon: const Icon(Icons.tune),
                label: const Text('Adjust XP'),
              ),
            ),
          ],

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('xp_history')
                  .orderBy('timestamp', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2));
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_outline,
                            size: 48, color: colors.onSurfaceVariant),
                        const SizedBox(height: 8),
                        Text(
                          'No XP earned yet',
                          style: textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant),
                        ),
                        Text(
                          'Complete chores or pay rent to earn XP!',
                          style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final amount = (data['amount'] as int?) ?? 0;
                    final description =
                        (data['description'] as String?) ?? 'XP earned';
                    final source =
                        (data['source'] as String?) ?? 'other';
                    final ts = data['timestamp'] as Timestamp?;
                    final isNegative = amount < 0;

                    final sourceIcon = switch (source) {
                      'chore' => Icons.checklist,
                      'rent' => Icons.home,
                      'expense' => Icons.account_balance_wallet,
                      'task' => Icons.task_alt,
                      'game' => Icons.sports_esports,
                      'checkin' => Icons.wb_sunny,
                      'grant' => Icons.card_giftcard,
                      'backfill' => Icons.history,
                      _ => Icons.star,
                    };

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: isNegative
                            ? colors.errorContainer
                            : colors.secondaryContainer,
                        radius: 18,
                        child: Icon(
                          isNegative ? Icons.remove_circle_outline : sourceIcon,
                          size: 16,
                          color: isNegative
                              ? colors.onErrorContainer
                              : colors.onSecondaryContainer,
                        ),
                      ),
                      title: Text(description, style: textTheme.bodyMedium),
                      subtitle: ts != null
                          ? Text(
                              _histFmt.format(ts.toDate()),
                              style: textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${amount >= 0 ? '+' : ''}$amount XP',
                            style: textTheme.labelLarge?.copyWith(
                              color: isNegative
                                  ? colors.error
                                  : colors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isViewerOwner) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: colors.error),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Delete entry',
                              onPressed: () => _confirmDeleteXpEntry(
                                context,
                                uid: user.uid,
                                entryId: doc.id,
                                description: description,
                                amount: amount,
                                source: source,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Delete XP entry ─────────────────────────────────────────────────────────

Future<void> _confirmDeleteXpEntry(
  BuildContext context, {
  required String uid,
  required String entryId,
  required String description,
  required int amount,
  required String source,
}) async {
  final colors = Theme.of(context).colorScheme;
  final hasChoreLink = source == 'chore';

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete XP entry?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"$description" (${amount >= 0 ? '+' : ''}$amount XP)'),
          const SizedBox(height: 8),
          Text(
            hasChoreLink
                ? 'This will remove the XP and delete the linked chore completion from their history.'
                : 'This will permanently remove the XP from their total.',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirm == true) {
    await XpService().deleteXpEntry(uid, entryId);
  }
}

// ─── Adjust XP sheet ──────────────────────────────────────────────────────────

Future<void> _showGrantXpSheet(
  BuildContext context,
  UserModel member,
  String householdId,
) async {
  final amountCtrl = TextEditingController();
  final reasonCtrl = TextEditingController();
  bool isGrant = true; // true = add XP, false = remove XP

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
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
              'Adjust XP — ${member.displayName}',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Current XP: ${member.totalXp}',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),

            // Grant / Remove toggle
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Grant XP'),
                  icon: Icon(Icons.add_circle_outline),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Remove XP'),
                  icon: Icon(Icons.remove_circle_outline),
                ),
              ],
              selected: {isGrant},
              onSelectionChanged: (v) => setS(() => isGrant = v.first),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'XP amount',
                suffixText: 'XP',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(
                  isGrant ? Icons.add : Icons.remove,
                  color: isGrant
                      ? Theme.of(ctx).colorScheme.primary
                      : Theme.of(ctx).colorScheme.error,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: isGrant
                    ? 'e.g. Helped with move-in 🙌'
                    : 'e.g. Chore incorrectly claimed',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: isGrant
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error,
                      foregroundColor: Theme.of(ctx).colorScheme.onError,
                    ),
              onPressed: () async {
                final raw = int.tryParse(amountCtrl.text.trim());
                final reason = reasonCtrl.text.trim();
                if (raw == null || raw <= 0 || reason.isEmpty) return;
                final amount = isGrant ? raw : -raw;
                await FirestoreService().grantXp(member.uid, amount, reason);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isGrant
                            ? '🎁 Granted $raw XP to ${member.displayName}!'
                            : '🗑️ Removed $raw XP from ${member.displayName}.',
                      ),
                    ),
                  );
                }
              },
              icon: Icon(isGrant ? Icons.card_giftcard : Icons.remove_circle),
              label: Text(isGrant ? 'Grant XP' : 'Remove XP'),
            ),
          ],
        ),
      ),
    ),
  );
}
