import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/household.dart';
import '../../models/level_system.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/household_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import 'member_detail_screen.dart';

/// Lists all household members with their roles.
///
/// The owner can change any member's role and remove members.
/// All members can see the invite code and copy it to the clipboard.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final HouseholdService _householdService = HouseholdService();

  Future<void> _changeRole(
    BuildContext context,
    String householdId,
    String uid,
    HouseholdRole currentRole,
  ) async {
    final newRole = await showDialog<HouseholdRole>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Change role'),
        children: HouseholdRole.values.map((role) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, role),
            child: Row(
              children: [
                Text(role.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Text(role.displayName),
                if (role == currentRole) ...[
                  const Spacer(),
                  const Icon(Icons.check, size: 18),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (newRole == null || newRole == currentRole) return;
    try {
      await _householdService.updateMemberRole(householdId, uid, newRole);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role updated to ${newRole.displayName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    String householdId,
    UserModel member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          'Remove ${member.displayName} from the household? '
          'They will need a new invite code to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await _householdService.removeMember(householdId, member.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.displayName} removed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final currentUid = auth.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
      ),
      body: StreamBuilder<UserModel?>(
        stream: auth.userProfileStream(),
        builder: (context, userSnap) {
          final householdId = userSnap.data?.householdId;

          if (userSnap.connectionState == ConnectionState.waiting &&
              !userSnap.hasData) {
            return const LoadingWidget(message: 'Loading…');
          }

          if (householdId == null) {
            return const EmptyState(
              icon: Icons.people_outline,
              title: 'No household',
              subtitle: 'Create or join a household to see members.',
            );
          }

          return StreamBuilder<Household?>(
            stream: _householdService.householdStream(householdId),
            builder: (context, householdSnap) {
              final household = householdSnap.data;
              if (household == null) {
                return const LoadingWidget(message: 'Loading household…');
              }

              final isOwner = household.ownerId == currentUid;

              return FutureBuilder<List<UserModel>>(
                // Re-fetch member profiles when membership changes.
                key: ValueKey(household.memberIds.join(',')),
                future: _householdService.fetchMembers(household.memberIds),
                builder: (context, membersSnap) {
                  if (!membersSnap.hasData) {
                    return const LoadingWidget(message: 'Loading members…');
                  }

                  final members = membersSnap.data!;

                  return CustomScrollView(
                    slivers: [
                      // ── Invite code card ────────────────────────────────
                      SliverToBoxAdapter(
                        child: _InviteCodeCard(
                          inviteCode: household.inviteCode,
                          memberCount: members.length,
                        ),
                      ),

                      // ── Section header ──────────────────────────────────
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            '${members.length} Member${members.length == 1 ? '' : 's'}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),

                      // ── Member list ─────────────────────────────────────
                      SliverList.separated(
                        itemCount: members.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 0),
                        itemBuilder: (context, i) {
                          final member = members[i];
                          final role = household.members[member.uid] ??
                              HouseholdRole.guest;
                          final isMe = member.uid == currentUid;

                          return _MemberTile(
                            member: member,
                            role: role,
                            isCurrentUser: isMe,
                            isOwner: isOwner,
                            onTap: () => _showMemberDetail(
                              context,
                              member: member,
                              role: role,
                            ),
                            onChangeRole: isOwner
                                ? () => _changeRole(
                                      context,
                                      householdId,
                                      member.uid,
                                      role,
                                    )
                                : null,
                            onRemove: (isOwner && !isMe)
                                ? () => _confirmRemove(
                                      context,
                                      householdId,
                                      member,
                                    )
                                : null,
                          );
                        },
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showMemberDetail(
    BuildContext context, {
    required UserModel member,
    required HouseholdRole role,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberDetailScreen(user: member, role: role),
      ),
    );
  }
}

// ─── Member detail bottom sheet ───────────────────────────────────────────────

class _MemberDetailSheet extends StatelessWidget {
  final UserModel member;
  final HouseholdRole role;

  const _MemberDetailSheet({required this.member, required this.role});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final levelInfo = LevelSystem.infoFor(member.level);
    final avatarEmoji = member.currentAvatar ?? levelInfo.avatarEmoji;
    final progress = LevelSystem.progressToNextLevel(member.totalXp, member.level);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: colors.onSurfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Big avatar
          CircleAvatar(
            radius: 48,
            backgroundColor: colors.primaryContainer,
            child: Text(avatarEmoji, style: const TextStyle(fontSize: 46)),
          ),
          const SizedBox(height: 16),

          // Name
          Text(
            member.displayName,
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),

          // Role badge
          _RoleBadge(role: role, tappable: false),
          const SizedBox(height: 16),

          // Level + XP card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Level ${member.level} — ${levelInfo.emoji} ${member.title ?? levelInfo.title}',
                        style: textTheme.titleSmall,
                      ),
                      Text(
                        '${member.totalXp} XP',
                        style: textTheme.titleSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: colors.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Joined date
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Joined ${_formatDate(member.createdAt)}',
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ─── Invite code card ─────────────────────────────────────────────────────────

class _InviteCodeCard extends StatelessWidget {
  final String inviteCode;
  final int memberCount;

  const _InviteCodeCard({
    required this.inviteCode,
    required this.memberCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: colors.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.key_rounded,
                      color: colors.onPrimaryContainer, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Invite Code',
                    style: textTheme.titleMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                inviteCode,
                style: textTheme.displaySmall?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Share this code with roommates to invite them.',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onPrimaryContainer.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invite code copied to clipboard!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy Invite Code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Member tile ──────────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  final UserModel member;
  final HouseholdRole role;
  final bool isCurrentUser;
  final bool isOwner;
  final VoidCallback onTap;
  final VoidCallback? onChangeRole;
  final VoidCallback? onRemove;

  const _MemberTile({
    required this.member,
    required this.role,
    required this.isCurrentUser,
    required this.isOwner,
    required this.onTap,
    this.onChangeRole,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final avatarColor =
        Color(int.parse(member.avatarColor.replaceFirst('#', 'FF'), radix: 16));
    final levelInfo = LevelSystem.infoFor(member.level);
    final avatarEmoji = member.currentAvatar ?? levelInfo.avatarEmoji;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar circle with emoji
                CircleAvatar(
                  backgroundColor: avatarColor,
                  foregroundColor: Colors.white,
                  radius: 22,
                  child: Text(
                    avatarEmoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + level title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              member.displayName,
                              style: textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrentUser) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'You',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colors.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${levelInfo.emoji} ${member.title ?? levelInfo.title} · ${role.displayName}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Role badge (tappable by owner to change)
                if (isOwner && !isCurrentUser)
                  InkWell(
                    onTap: onChangeRole,
                    borderRadius: BorderRadius.circular(20),
                    child: _RoleBadge(role: role, tappable: true),
                  )
                else
                  _RoleBadge(role: role, tappable: false),

                // Remove button (owner only, not self)
                if (onRemove != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.person_remove_outlined,
                        color: colors.error, size: 20),
                    tooltip: 'Remove member',
                    onPressed: onRemove,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Role badge ───────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final HouseholdRole role;
  final bool tappable;

  const _RoleBadge({required this.role, required this.tappable});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: tappable
            ? Border.all(
                color: colors.outline.withOpacity(0.5),
                width: 1,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(role.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            role.displayName,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (tappable) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 16, color: colors.onSurfaceVariant),
          ],
        ],
      ),
    );
  }
}
