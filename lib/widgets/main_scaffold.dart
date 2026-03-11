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
import '../screens/profile/profile_screen.dart';
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
/// - owner/renter: Home, Expenses, Chores+Tasks, Events, Profile
/// - princess:     Home, Expenses, Chores+Tasks, Events, Profile
/// - guest:        Home, Events, Profile
/// - no household: all tabs shown (each screen handles the empty state)
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;

  void _switchTab(int index) => setState(() => _selectedIndex = index);

  /// All possible pages — built with tab-switch callback for HomeScreen.
  List<Widget> get _allPages => [
    HomeScreen(onSwitchTab: _switchTab), // 0
    ExpensesScreen(),                    // 1
    ChoresScreen(),                      // 2
    EventsScreen(),                      // 3
    ProfileScreen(),                     // 4
  ];

  /// Pages that have been visited at least once and should be kept alive.
  final _visitedPages = <int>{};

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

    // Expenses + Chores: everyone except guests.
    if (role == null || role != HouseholdRole.guest) {
      tabs.add(const _Tab(
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: 'Expenses',
        ),
        1,
      ));
      tabs.add(const _Tab(
        NavigationDestination(
          icon: Icon(Icons.checklist_outlined),
          selectedIcon: Icon(Icons.checklist),
          label: 'Chores',
        ),
        2,
      ));
    }

    // Events: everyone.
    tabs.add(const _Tab(
      NavigationDestination(
        icon: Icon(Icons.event_outlined),
        selectedIcon: Icon(Icons.event),
        label: 'Events',
      ),
      3,
    ));

    // Profile: always.
    tabs.add(const _Tab(
      NavigationDestination(
        icon: Icon(Icons.person_outlined),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
      4,
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

    // Mark this page as visited so it gets built.
    _visitedPages.add(pageIndex);

    return Scaffold(
      body: IndexedStack(
        index: pageIndex,
        children: List.generate(_allPages.length, (i) {
          if (!_visitedPages.contains(i)) return const SizedBox.shrink();
          return _allPages[i];
        }),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: tabs.map((t) => t.destination).toList(),
      ),
    );
  }
}
