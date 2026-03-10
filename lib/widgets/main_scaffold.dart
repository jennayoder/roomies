import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/household.dart';
import '../models/user_model.dart';
import '../screens/chores/chores_screen.dart';
import '../screens/events/events_screen.dart';
import '../screens/expenses/expenses_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/members/members_screen.dart';
import '../screens/rent/rent_screen.dart';
import '../services/auth_service.dart';
import '../services/household_service.dart';

/// Pairs a [NavigationDestination] with the index into [_allPages].
class _Tab {
  final NavigationDestination destination;
  final int pageIndex;
  const _Tab(this.destination, this.pageIndex);
}

/// The main app shell with a role-aware [NavigationBar].
///
/// Tabs shown depend on the current user's [HouseholdRole]:
/// - owner/renter: Home, Rent, Expenses, Chores, Events, Members
/// - princess:     Home, Expenses, Chores, Events, Members
/// - guest:        Home, Events, Members
/// - no household: all tabs shown (each screen handles the empty state)
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  /// Index within the currently visible tab list (NOT the page index).
  int _selectedIndex = 0;

  /// All possible pages — always in the [IndexedStack] to preserve state.
  static const List<Widget> _allPages = [
    HomeScreen(),      // page 0
    RentScreen(),      // page 1
    ExpensesScreen(),  // page 2
    ChoresScreen(),    // page 3
    EventsScreen(),    // page 4
    MembersScreen(),   // page 5
  ];

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

    // Rent: owner and renter only (hidden for princess, guest, no-household).
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

    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // Watch the user profile to get householdId and then the household role.
    return StreamBuilder<UserModel?>(
      stream: auth.userProfileStream(),
      builder: (context, userSnap) {
        final householdId = userSnap.data?.householdId;

        if (householdId == null) {
          // Not in a household yet — show all tabs (screens handle empty state).
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

    // Clamp selected index in case tabs changed (e.g. role downgrade).
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
