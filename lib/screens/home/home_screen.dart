import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/household_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

/// Dashboard tab — shows a summary of the household and quick stats.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HouseholdService _householdService = HouseholdService();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final colors = Theme.of(context).colorScheme;

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

          return _HouseholdDashboard(householdId: user.householdId!);
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
  const _HouseholdDashboard({required this.householdId});

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

            // ── Quick stats grid ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Quick Overview',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: const [
                  _StatCard(
                    icon: Icons.receipt_long,
                    label: 'Rent',
                    value: 'See Rent tab',
                    color: Color(0xFF006874),
                  ),
                  _StatCard(
                    icon: Icons.account_balance_wallet,
                    label: 'Expenses',
                    value: 'See Expenses tab',
                    color: Color(0xFF6750A4),
                  ),
                  _StatCard(
                    icon: Icons.checklist,
                    label: 'Chores',
                    value: 'See Chores tab',
                    color: Color(0xFF386A20),
                  ),
                  _StatCard(
                    icon: Icons.event,
                    label: 'Events',
                    value: 'See Events tab',
                    color: Color(0xFF8B4000),
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
