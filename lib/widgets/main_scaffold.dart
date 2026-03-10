import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/household.dart';
import '../models/level_system.dart';
import '../models/user_model.dart';
import '../screens/chores/chores_screen.dart';
import '../screens/events/events_screen.dart';
import '../screens/expenses/expenses_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/leaderboard/leaderboard_screen.dart';
import '../screens/members/members_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/rent/rent_screen.dart';
import '../screens/tasks/personal_tasks_screen.dart';
import '../services/auth_service.dart';
import '../services/household_service.dart';
import '../services/theme_notifier.dart';
import '../services/xp_service.dart';

/// Pairs a [NavigationDestination] with the index into [_allPages].
class _Tab {
  final NavigationDestination destination;
  final int pageIndex;
  const _Tab(this.destination, this.pageIndex);
}

/// The main app shell with a role-aware [NavigationBar].
///
/// Tabs shown depend on the current user's [HouseholdRole]:
/// - owner/renter: Home, Rent, Expenses, Chores, Events, Members, Leaderboard, Tasks, Profile
/// - princess:     Home, Expenses, Chores, Events, Members, Leaderboard, Tasks, Profile
/// - guest:        Home, Events, Members, Leaderboard, Profile
/// - no household: all tabs shown (each screen handles the empty state)
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;

  /// All possible pages — always in the [IndexedStack] to preserve state.
  static const List<Widget> _allPages = [
    HomeScreen(),          // 0
    RentScreen(),          // 1
    ExpensesScreen(),      // 2
    ChoresScreen(),        // 3
    EventsScreen(),        // 4
    MembersScreen(),       // 5
    LeaderboardScreen(),   // 6
    PersonalTasksScreen(), // 7
    ProfileScreen(),       // 8
  ];

  StreamSubscription<UserModel?>? _profileSub;

  /// Tracks level-ups we've already shown this session to avoid re-showing.
  final _shownLevelUps = <int>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _profileSub?.cancel();
    final auth = context.read<AuthService>();
    _profileSub = auth.userProfileStream().listen((user) {
      if (!mounted) return;

      // Apply persisted theme when profile first loads.
      if (user?.currentTheme != null) {
        final color = LevelSystem.hexToColor(user!.currentTheme!);
        context.read<ThemeNotifier>().setSeedColor(color);
      }

      // Show level-up dialog if there's a pending level-up.
      final pending = user?.pendingLevelUp;
      if (pending != null && !_shownLevelUps.contains(pending)) {
        _shownLevelUps.add(pending);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showLevelUpDialog(pending, user!);
        });
      }
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  void _showLevelUpDialog(int newLevel, UserModel user) {
    final uid = context.read<AuthService>().currentUser?.uid;
    if (uid == null) return;

    // Clear the flag so it isn't shown again after a hot-restart or re-login.
    XpService().clearPendingLevelUp(uid);

    final info = LevelSystem.infoFor(newLevel);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: Text(info.emoji, style: const TextStyle(fontSize: 48)),
        title: const Text('Level Up!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You reached Level $newLevel',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              info.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            if (newLevel < LevelSystem.maxLevel) ...[
              const SizedBox(height: 12),
              Text(
                '🎨 New avatar & theme color unlocked!\nCheck your Profile to equip them.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Awesome! 🎉'),
          ),
        ],
      ),
    );
  }

  /// Builds the visible tab list for the given [role].
  List<_Tab> _buildTabs(HouseholdRole? role) {
    final tabs = <_Tab>[
      const _Tab(
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        0,
      ),
    ];

    // Rent: owner and renter only.
    if (role == null ||
        role == HouseholdRole.owner ||
        role == HouseholdRole.renter) {
      tabs.add(const _Tab(
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'Rent',
        ),
        1,
      ));
    }

    // Expenses + Chores: everyone except guests.
    if (role == null || role != HouseholdRole.guest) {
      tabs.add(const _Tab(
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: 'Expenses',
        ),
        2,
      ));
      tabs.add(const _Tab(
        NavigationDestination(
          icon: Icon(Icons.checklist_outlined),
          selectedIcon: Icon(Icons.checklist),
          label: 'Chores',
        ),
        3,
      ));
    }

    // Events and Members: everyone.
    tabs.add(const _Tab(
      NavigationDestination(
        icon: Icon(Icons.event_outlined),
        selectedIcon: Icon(Icons.event),
        label: 'Events',
      ),
      4,
    ));
    tabs.add(const _Tab(
      NavigationDestination(
        icon: Icon(Icons.people_outlined),
        selectedIcon: Icon(Icons.people),
        label: 'Members',
      ),
      5,
    ));

    // Leaderboard: everyone.
    tabs.add(const _Tab(
      NavigationDestination(
        icon: Icon(Icons.emoji_events_outlined),
        selectedIcon: Icon(Icons.emoji_events),
        label: 'Rankings',
      ),
      6,
    ));

    // Tasks: everyone except guests.
    if (role == null || role != HouseholdRole.guest) {
      tabs.add(const _Tab(
        NavigationDestination(
          icon: Icon(Icons.task_alt_outlined),
          selectedIcon: Icon(Icons.task_alt),
          label: 'Tasks',
        ),
        7,
      ));
    }

    // Profile: always.
    tabs.add(const _Tab(
      NavigationDestination(
        icon: Icon(Icons.person_outlined),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
      8,
    ));

    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return StreamBuilder<UserModel?>(
      stream: auth.userProfileStream(),
      builder: (context, userSnap) {
        final householdId = userSnap.data?.householdId;

        if (householdId == null) {
          return _buildScaffold(null);
        }

        return StreamBuilder<Household?>(
          stream: HouseholdService().householdStream(householdId),
          builder: (context, householdSnap) {
            final role = householdSnap.data?.members[auth.currentUser?.uid];
            return _buildScaffold(role);
          },
        );
      },
    );
  }

  Widget _buildScaffold(HouseholdRole? role) {
    final tabs = _buildTabs(role);
    final safeIndex = _selectedIndex.clamp(0, tabs.length - 1);
    final pageIndex = tabs[safeIndex].pageIndex;

    return Scaffold(
      body: IndexedStack(
        index: pageIndex,
        children: _allPages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: tabs.map((t) => t.destination).toList(),
      ),
    );
  }
}
