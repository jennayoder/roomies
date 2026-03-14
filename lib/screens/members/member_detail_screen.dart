import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/household.dart';
import '../../models/level_system.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';

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
        HouseholdRole.guest => '🎉 Guest',
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

          // Grant XP button — owner only, not for themselves
          if (isViewerOwner &&
              role != HouseholdRole.owner &&
              viewerHouseholdId != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () =>
                    _showGrantXpSheet(context, user, viewerHouseholdId!),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Grant XP'),
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
                    final data =
                        docs[i].data() as Map<String, dynamic>;
                    final amount = (data['amount'] as int?) ?? 0;
                    final description =
                        (data['description'] as String?) ?? 'XP earned';
                    final source =
                        (data['source'] as String?) ?? 'other';
                    final ts = data['timestamp'] as Timestamp?;

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
                        backgroundColor: colors.secondaryContainer,
                        radius: 18,
                        child: Icon(sourceIcon,
                            size: 16, color: colors.onSecondaryContainer),
                      ),
                      title: Text(description,
                          style: textTheme.bodyMedium),
                      subtitle: ts != null
                          ? Text(
                              _histFmt.format(ts.toDate()),
                              style: textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant),
                            )
                          : null,
                      trailing: Text(
                        '+$amount XP',
                        style: textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
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

// ─── Grant XP sheet ───────────────────────────────────────────────────────────

Future<void> _showGrantXpSheet(
  BuildContext context,
  UserModel member,
  String householdId,
) async {
  final amountCtrl = TextEditingController();
  final reasonCtrl = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
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
            'Grant XP to ${member.displayName}',
            style: Theme.of(ctx).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'XP amount',
              suffixText: 'XP',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'e.g. Helped with move-in 🙌',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final amount = int.tryParse(amountCtrl.text.trim());
              final reason = reasonCtrl.text.trim();
              if (amount == null || amount <= 0 || reason.isEmpty) return;
              await FirestoreService().grantXp(member.uid, amount, reason);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          '🎁 Granted $amount XP to ${member.displayName}!')),
                );
              }
            },
            icon: const Icon(Icons.card_giftcard),
            label: const Text('Grant XP'),
          ),
        ],
      ),
    ),
  );
}
