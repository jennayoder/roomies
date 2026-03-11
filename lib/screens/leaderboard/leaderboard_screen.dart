import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/household.dart';
import '../../models/level_system.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../members/member_detail_screen.dart';

/// Leaderboard tab — shows all household members ranked by total XP.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return StreamBuilder<UserModel?>(
      stream: auth.userProfileStream(),
      builder: (context, snapshot) {
        final householdId = snapshot.data?.householdId;
        if (householdId == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Leaderboard')),
            body: const EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No household',
              subtitle: 'Join or create a household from the Home tab.',
            ),
          );
        }
        return _LeaderboardContent(
          householdId: householdId,
          currentUid: auth.currentUser!.uid,
        );
      },
    );
  }
}

class _LeaderboardContent extends StatefulWidget {
  final String householdId;
  final String currentUid;

  const _LeaderboardContent({
    required this.householdId,
    required this.currentUid,
  });

  @override
  State<_LeaderboardContent> createState() => _LeaderboardContentState();
}

class _LeaderboardContentState extends State<_LeaderboardContent> {
  late Future<List<(UserModel, HouseholdRole)>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _membersFuture = FirestoreService().getHouseholdMembers(widget.householdId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: RefreshIndicator(
        onRefresh: () async => setState(_load),
        child: FutureBuilder<List<(UserModel, HouseholdRole)>>(
          future: _membersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingWidget(message: 'Loading leaderboard…');
            }

            final members = snapshot.data ?? [];
            if (members.isEmpty) {
              return const EmptyState(
                icon: Icons.emoji_events_outlined,
                title: 'No members yet',
                subtitle: 'Pull down to refresh.',
              );
            }

            final sorted = [...members]
              ..sort((a, b) => b.$1.totalXp.compareTo(a.$1.totalXp));

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final (user, _) = sorted[index];
                return _LeaderboardCard(
                  user: user,
                  role: sorted[index].$2,
                  rank: index + 1,
                  isMe: user.uid == widget.currentUid,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  final UserModel user;
  final HouseholdRole role;
  final int rank;
  final bool isMe;

  const _LeaderboardCard({
    required this.user,
    required this.role,
    required this.rank,
    required this.isMe,
  });

  String get _medal => switch (rank) {
        1 => '🥇',
        2 => '🥈',
        3 => '🥉',
        _ => '#$rank',
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final levelInfo = LevelSystem.infoFor(user.level);
    final avatarEmoji = user.currentAvatar ?? levelInfo.avatarEmoji;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isMe ? colors.primaryContainer : null,
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemberDetailScreen(user: user, role: role),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              child: Text(
                _medal,
                style: rank <= 3
                    ? const TextStyle(fontSize: 24)
                    : TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.onSurfaceVariant,
                        fontSize: 14,
                      ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 6),
            CircleAvatar(
              backgroundColor: colors.secondaryContainer,
              child: Text(avatarEmoji, style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                user.displayName,
                overflow: TextOverflow.ellipsis,
                style: isMe
                    ? TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.onPrimaryContainer,
                      )
                    : null,
              ),
            ),
            if (isMe) ...[
              const SizedBox(width: 4),
              Text(
                '(you)',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onPrimaryContainer.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${levelInfo.emoji} ${user.title ?? levelInfo.title}  ·  Lvl ${user.level}',
          style: TextStyle(
            color: isMe ? colors.onPrimaryContainer.withOpacity(0.75) : null,
            fontSize: 12,
          ),
        ),
        trailing: Text(
          '${user.totalXp} XP',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: isMe ? colors.onPrimaryContainer : colors.primary,
          ),
        ),
      ),
    );
  }
}
