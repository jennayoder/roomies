import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/event.dart';
import '../../models/household.dart';
import '../../models/level_system.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/household_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../members/members_screen.dart';
import '../rent/rent_screen.dart';

final _eventDateFmt = DateFormat('EEE, MMM d · h:mm a');

/// Dashboard tab — shows a summary of the household and quick stats.
class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onSwitchTab;
  const HomeScreen({super.key, this.onSwitchTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HouseholdService _householdService = HouseholdService();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roomies'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await auth.signOut();
              }
            },
          ),
        ],
      ),
      body: StreamBuilder(
        stream: auth.userProfileStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget(message: 'Loading your household…');
          }

          final user = snapshot.data;
          if (user == null) {
            return const LoadingWidget(message: 'Loading profile…');
          }

          if (user.householdId == null) {
            // User is not in a household yet — prompt to create or join.
            return _NoHouseholdView(householdService: _householdService);
          }

          return _HouseholdDashboard(
            householdId: user.householdId!,
            currentUid: auth.currentUser?.uid ?? '',
            onSwitchTab: widget.onSwitchTab,
          );
        },
      ),
    );
  }
}

// ─── No-household placeholder ─────────────────────────────────────────────────

class _NoHouseholdView extends StatefulWidget {
  final HouseholdService householdService;
  const _NoHouseholdView({required this.householdService});

  @override
  State<_NoHouseholdView> createState() => _NoHouseholdViewState();
}

class _NoHouseholdViewState extends State<_NoHouseholdView> {
  bool _isLoading = false;

  Future<void> _createHousehold() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Household'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Household name',
            hintText: 'e.g. The Loft',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final household = await widget.householdService.createHousehold(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Household "${household.name}" created! '
              'Invite code: ${household.inviteCode}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinHousehold() async {
    final codeCtrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Household'),
        content: TextField(
          controller: codeCtrl,
          decoration: const InputDecoration(
            labelText: 'Invite code',
            hintText: 'e.g. AB12CD',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, codeCtrl.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (code == null || code.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final household = await widget.householdService.joinHousehold(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined "${household.name}"!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingWidget(message: 'Setting up household…');
    }

    return EmptyState(
      icon: Icons.house_outlined,
      title: 'No household yet',
      subtitle: 'Create a new household or join one with an invite code.',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _createHousehold,
            icon: const Icon(Icons.add),
            label: const Text('Create'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _joinHousehold,
            icon: const Icon(Icons.group_add),
            label: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

// ─── Household dashboard ──────────────────────────────────────────────────────

class _HouseholdDashboard extends StatelessWidget {
  final String householdId;
  final String currentUid;
  final void Function(int)? onSwitchTab;

  const _HouseholdDashboard({
    required this.householdId,
    required this.currentUid,
    this.onSwitchTab,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final householdService = HouseholdService();

    return StreamBuilder(
      stream: householdService.householdStream(householdId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoadingWidget(message: 'Loading household…');
        }

        final household = snapshot.data!;
        final role = household.members[currentUid];
        final canSeeRent = role == null ||
            role == HouseholdRole.owner ||
            role == HouseholdRole.renter;

        return CustomScrollView(
          slivers: [
            // ── Household header card ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
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
                            Icon(Icons.house_rounded,
                                color: colors.onPrimaryContainer, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                household.name,
                                style: textTheme.headlineSmall?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.people_outlined,
                                color: colors.onPrimaryContainer, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${household.memberIds.length} member${household.memberIds.length == 1 ? '' : 's'}',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Invite code chip
                        InkWell(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Invite code: ${household.inviteCode}'),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Chip(
                            avatar: Icon(Icons.key,
                                color: colors.onPrimaryContainer, size: 16),
                            label: Text(
                              'Code: ${household.inviteCode}',
                              style: TextStyle(color: colors.onPrimaryContainer),
                            ),
                            backgroundColor:
                                colors.primary.withOpacity(0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Quick access row (Rent only) ───────────────────────────
            if (canSeeRent) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Text(
                    'Quick Access',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _TappableCard(
                      icon: Icons.receipt_long,
                      label: 'Rent',
                      subtitle: 'View & pay rent',
                      color: const Color(0xFF006874),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RentScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Rankings preview ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '🏆 Rankings',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LeaderboardScreen()),
                      ),
                      child: const Text('See all'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: _MiniLeaderboard(householdId: householdId),
              ),
            ),

            // ── Members dropdown ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: _ExpandableMembersCard(
                  householdId: householdId,
                  household: household,
                ),
              ),
            ),

            // ── Upcoming Events ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '📅 Upcoming Events',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: () => onSwitchTab?.call(3),
                      child: const Text('See all'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: _UpcomingEvents(
                  householdId: householdId,
                  onSeeAll: () => onSwitchTab?.call(3),
                ),
              ),
            ),

            // ── Quick nav cards ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Text(
                  'Quick Access',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _TappableCard(
                    icon: Icons.account_balance_wallet,
                    label: 'Expenses',
                    subtitle: 'View & split costs',
                    color: const Color(0xFF6750A4),
                    onTap: () => onSwitchTab?.call(1),
                  ),
                  _TappableCard(
                    icon: Icons.checklist,
                    label: 'Chores',
                    subtitle: 'Tasks & XP chores',
                    color: const Color(0xFF386A20),
                    onTap: () => onSwitchTab?.call(2),
                  ),
                  _TappableCard(
                    icon: Icons.event,
                    label: 'Events',
                    subtitle: 'Household calendar',
                    color: const Color(0xFF8B4000),
                    onTap: () => onSwitchTab?.call(3),
                  ),
                  if (role == HouseholdRole.owner)
                    _TappableCard(
                      icon: Icons.people,
                      label: 'Members',
                      subtitle: 'Manage household',
                      color: const Color(0xFF6750A4),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MembersScreen()),
                      ),
                    ),
                  _TappableCard(
                    icon: Icons.person,
                    label: 'Profile',
                    subtitle: 'XP, level & avatars',
                    color: const Color(0xFF006874),
                    onTap: () => onSwitchTab?.call(4),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Tappable quick-access card ───────────────────────────────────────────────

class _TappableCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _TappableCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Upcoming events ──────────────────────────────────────────────────────────

class _UpcomingEvents extends StatelessWidget {
  final String householdId;
  final VoidCallback? onSeeAll;
  const _UpcomingEvents({required this.householdId, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();

    return StreamBuilder<List<Event>>(
      stream: FirestoreService().eventsStream(householdId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final upcoming = (snapshot.data ?? [])
            .where((e) => e.dateTime.isAfter(now))
            .toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

        if (upcoming.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.event_outlined,
                      color: colors.onSurfaceVariant, size: 20),
                  const SizedBox(width: 12),
                  Text('No upcoming events',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
          );
        }

        final preview = upcoming.take(3).toList();
        return Card(
          child: Column(
            children: [
              for (int i = 0; i < preview.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: colors.tertiaryContainer,
                    radius: 20,
                    child: Text(
                      preview[i].dateTime.day.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.onTertiaryContainer,
                      ),
                    ),
                  ),
                  title: Text(preview[i].title,
                      style:
                          textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _eventDateFmt.format(preview[i].dateTime),
                    style: textTheme.bodySmall,
                  ),
                  trailing: preview[i].location != null
                      ? Icon(Icons.location_on_outlined,
                          size: 16, color: colors.onSurfaceVariant)
                      : null,
                  onTap: onSeeAll,
                ),
              ],
              if (upcoming.length > 3) ...[
                const Divider(height: 1),
                TextButton(
                  onPressed: onSeeAll,
                  child: Text('+${upcoming.length - 3} more events'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Expandable members card ──────────────────────────────────────────────────

class _ExpandableMembersCard extends StatefulWidget {
  final String householdId;
  final Household household;

  const _ExpandableMembersCard({
    required this.householdId,
    required this.household,
  });

  @override
  State<_ExpandableMembersCard> createState() => _ExpandableMembersCardState();
}

class _ExpandableMembersCardState extends State<_ExpandableMembersCard> {
  late Future<List<(UserModel, HouseholdRole)>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(_ExpandableMembersCard old) {
    super.didUpdateWidget(old);
    if (old.householdId != widget.householdId ||
        old.household.memberIds.length != widget.household.memberIds.length) {
      _reload();
    }
  }

  void _reload() {
    _membersFuture =
        FirestoreService().getHouseholdMembers(widget.householdId);
  }

  String _roleLabel(HouseholdRole role) => switch (role) {
        HouseholdRole.owner => '👑 Owner',
        HouseholdRole.renter => '🏠 Roomie',
        HouseholdRole.princess => '👸 Princess',
        HouseholdRole.guest => '🎉 Guest',
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<List<(UserModel, HouseholdRole)>>(
      future: _membersFuture,
      builder: (context, snapshot) {
        final members = snapshot.data ?? [];

        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: const Icon(Icons.people_outlined),
            title: Text(
              '👥 Members',
              style: textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${widget.household.memberIds.length} member${widget.household.memberIds.length == 1 ? '' : 's'}',
              style: textTheme.bodySmall,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MembersScreen()),
                  ),
                  child: const Text('Manage'),
                ),
                const Icon(Icons.expand_more),
              ],
            ),
            children: snapshot.connectionState == ConnectionState.waiting
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  ]
                : members.isEmpty
                    ? [
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No members found.'),
                        )
                      ]
                    : members
                        .map(
                          (m) => ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colors.secondaryContainer,
                              child: Text(
                                m.$1.currentAvatar ??
                                    LevelSystem.infoFor(m.$1.level).avatarEmoji,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                            title: Text(m.$1.displayName),
                            subtitle: Text(
                              '${_roleLabel(m.$2)}  ·  Lvl ${m.$1.level} · ${m.$1.totalXp} XP',
                              style: textTheme.bodySmall,
                            ),
                          ),
                        )
                        .toList(),
          ),
        );
      },
    );
  }
}

// ─── Mini leaderboard ─────────────────────────────────────────────────────────

class _MiniLeaderboard extends StatefulWidget {
  final String householdId;
  const _MiniLeaderboard({required this.householdId});

  @override
  State<_MiniLeaderboard> createState() => _MiniLeaderboardState();
}

class _MiniLeaderboardState extends State<_MiniLeaderboard> {
  late Future<List<(UserModel, dynamic)>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getHouseholdMembers(widget.householdId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<List<(UserModel, dynamic)>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final sorted = [...snapshot.data!]
          ..sort((a, b) => b.$1.totalXp.compareTo(a.$1.totalXp));
        final top = sorted.take(3).toList();

        return Card(
          child: Column(
            children: [
              for (int i = 0; i < top.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: Text(
                    ['🥇', '🥈', '🥉'][i],
                    style: const TextStyle(fontSize: 20),
                  ),
                  title: Text(
                    top[i].$1.displayName,
                    style: textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${LevelSystem.infoFor(top[i].$1.level).emoji} '
                    '${top[i].$1.title ?? LevelSystem.infoFor(top[i].$1.level).title}',
                    style: textTheme.bodySmall,
                  ),
                  trailing: Text(
                    '${top[i].$1.totalXp} XP',
                    style: textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Info stat card ───────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: textTheme.labelMedium?.copyWith(color: color),
                ),
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
