import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/household.dart';
import '../../models/rent_entry.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/household_service.dart';
import '../../services/xp_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

final _currencyFmt = NumberFormat.currency(symbol: '\$');
final _periodFmt = DateFormat('MMMM yyyy');

class RentScreen extends StatelessWidget {
  const RentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return StreamBuilder<UserModel?>(
      stream: auth.userProfileStream(),
      builder: (context, snap) {
        final user = snap.data;
        if (user?.householdId == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Rent')),
            body: const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No household',
              subtitle: 'Join or create a household from the Home tab.',
            ),
          );
        }
        return _RentContent(
          householdId: user!.householdId!,
          currentUid: auth.currentUser!.uid,
        );
      },
    );
  }
}

class _RentContent extends StatelessWidget {
  final String householdId;
  final String currentUid;
  const _RentContent({required this.householdId, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();

    return StreamBuilder<Household?>(
      stream: HouseholdService().householdStream(householdId),
      builder: (context, householdSnap) {
        final role = householdSnap.data?.members[currentUid];
        final isOwner = role == HouseholdRole.owner;

        return Scaffold(
          appBar: AppBar(title: const Text('Rent')),
          floatingActionButton: isOwner
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddRentSheet(
                    context,
                    householdId: householdId,
                    currentUid: currentUid,
                    service: service,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Assign Rent'),
                )
              : null,
          body: StreamBuilder<List<RentEntry>>(
            stream: service.rentStream(householdId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingWidget(message: 'Loading rent…');
              }

              final all = snapshot.data ?? [];

              // Filter: owner sees all; renters only see entries they're in
              final entries = isOwner
                  ? all
                  : all
                      .where((e) => e.memberShares.containsKey(currentUid))
                      .toList();

              if (entries.isEmpty) {
                return EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: isOwner ? 'No rent entries yet' : 'No rent assigned to you',
                  subtitle: isOwner
                      ? 'Tap "Assign Rent" to set up rent for your renters.'
                      : 'Your landlord hasn\'t assigned rent yet.',
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _RentEntryCard(
                  entry: entries[i],
                  householdId: householdId,
                  currentUid: currentUid,
                  isOwner: isOwner,
                  service: service,
                  onTap: () => _showRentDetailSheet(
                    context,
                    entry: entries[i],
                    householdId: householdId,
                    currentUid: currentUid,
                    isOwner: isOwner,
                    service: service,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─── Rent entry card ──────────────────────────────────────────────────────────

class _RentEntryCard extends StatelessWidget {
  final RentEntry entry;
  final String householdId;
  final String currentUid;
  final bool isOwner;
  final FirestoreService service;
  final VoidCallback? onTap;

  const _RentEntryCard({
    required this.entry,
    required this.householdId,
    required this.currentUid,
    required this.isOwner,
    required this.service,
    this.onTap,
  });

  String _periodLabel(String period) {
    try {
      final dt = DateFormat('yyyy-MM').parse(period);
      return _periodFmt.format(dt);
    } catch (_) {
      return period;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final myShare = entry.memberShares[currentUid];
    final iHavePaid = entry.paidStatus[currentUid] ?? false;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _periodLabel(entry.period),
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (entry.isRecurring)
                        Text(
                          '🔁 Recurring monthly',
                          style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (entry.isFullyPaid)
                  Chip(
                    label: const Text('Fully Paid ✅'),
                    backgroundColor: colors.tertiaryContainer,
                    labelStyle:
                        TextStyle(color: colors.onTertiaryContainer),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Owner sees total + all members; renter sees only their share
            if (isOwner) ...[
              Text(
                'Total: ${_currencyFmt.format(entry.totalAmount)}',
                style: textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...entry.memberShares.entries.map((e) {
                final paid = entry.paidStatus[e.key] ?? false;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        paid ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 16,
                        color: paid ? colors.primary : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MemberName(uid: e.key, householdId: householdId),
                      ),
                      Text(
                        _currencyFmt.format(e.value),
                        style: textTheme.bodyMedium?.copyWith(
                          color: paid ? colors.primary : null,
                          decoration:
                              paid ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (!paid) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => service.markMemberRentPaid(
                              householdId, entry.id, e.key),
                          child: const Text('Mark Paid'),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ] else if (myShare != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Your share:', style: textTheme.bodyMedium),
                  Text(
                    _currencyFmt.format(myShare),
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: iHavePaid ? colors.primary : colors.error,
                    ),
                  ),
                ],
              ),
            ],

            // Pay button for renters
            if (!isOwner && myShare != null && !iHavePaid) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await service.markMemberRentPaid(
                        householdId, entry.id, currentUid);
                    await XpService().awardRentPaidOnTime(
                        currentUid, householdId);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Mark My Rent Paid (+20 XP)'),
                ),
              ),
            ] else if (!isOwner && iHavePaid) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle, color: colors.primary, size: 18),
                  const SizedBox(width: 6),
                  Text('You paid ✅',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: colors.primary)),
                ],
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

// ─── Rent detail sheet ────────────────────────────────────────────────────────

Future<void> _showRentDetailSheet(
  BuildContext context, {
  required RentEntry entry,
  required String householdId,
  required String currentUid,
  required bool isOwner,
  required FirestoreService service,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _RentDetailSheet(
      entry: entry,
      householdId: householdId,
      currentUid: currentUid,
      isOwner: isOwner,
      service: service,
    ),
  );
}

class _RentDetailSheet extends StatelessWidget {
  final RentEntry entry;
  final String householdId;
  final String currentUid;
  final bool isOwner;
  final FirestoreService service;

  const _RentDetailSheet({
    required this.entry,
    required this.householdId,
    required this.currentUid,
    required this.isOwner,
    required this.service,
  });

  String _periodLabel(String period) {
    try {
      final dt = DateFormat('yyyy-MM').parse(period);
      return _periodFmt.format(dt);
    } catch (_) {
      return period;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final myShare = entry.memberShares[currentUid];
    final iHavePaid = entry.paidStatus[currentUid] ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colors.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title row
          Row(
            children: [
              Expanded(
                child: Text(
                  _periodLabel(entry.period),
                  style: textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (entry.isFullyPaid)
                Chip(
                  label: const Text('Fully Paid ✅'),
                  backgroundColor: colors.tertiaryContainer,
                  labelStyle: TextStyle(color: colors.onTertiaryContainer),
                ),
            ],
          ),
          if (entry.isRecurring) ...[
            const SizedBox(height: 4),
            Text('🔁 Recurring monthly',
                style: textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: textTheme.bodyMedium),
              Text(
                _currencyFmt.format(entry.totalAmount),
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(height: 24),

          // Member shares with paid status
          ...entry.memberShares.entries.map((e) {
            final paid = entry.paidStatus[e.key] ?? false;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(
                    paid ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 18,
                    color: paid ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MemberName(uid: e.key, householdId: householdId),
                  ),
                  Text(
                    _currencyFmt.format(e.value),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: paid ? colors.primary : null,
                      decoration: paid ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  // Owner: mark paid per member
                  if (isOwner && !paid) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        await service.markMemberRentPaid(
                            householdId, entry.id, e.key);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Mark Paid'),
                    ),
                  ],
                ],
              ),
            );
          }),

          // Renter: pay my share
          if (!isOwner && myShare != null && !iHavePaid) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                await service.markMemberRentPaid(
                    householdId, entry.id, currentUid);
                await XpService().awardRentPaidOnTime(currentUid, householdId);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.check),
              label: const Text('Mark My Rent Paid (+20 XP)'),
            ),
          ],

          // Owner: delete
          if (isOwner) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('Delete rent entry?'),
                    content: const Text(
                        'This will permanently remove this rent entry.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: colors.error),
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await service.deleteRentEntry(householdId, entry.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete Entry'),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Member name resolver ─────────────────────────────────────────────────────

class _MemberName extends StatefulWidget {
  final String uid;
  final String householdId;
  const _MemberName({required this.uid, required this.householdId});

  @override
  State<_MemberName> createState() => _MemberNameState();
}

class _MemberNameState extends State<_MemberName> {
  String _name = '…';

  @override
  void initState() {
    super.initState();
    FirestoreService().getHouseholdMembers(widget.householdId).then((members) {
      final match = members.where((m) => m.$1.uid == widget.uid).firstOrNull;
      if (match != null && mounted) {
        setState(() => _name = match.$1.displayName);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Text(_name);
}

// ─── Add rent sheet ───────────────────────────────────────────────────────────

Future<void> _showAddRentSheet(
  BuildContext context, {
  required String householdId,
  required String currentUid,
  required FirestoreService service,
}) async {
  final allMembers = await FirestoreService().getHouseholdMembers(householdId);
  final renters = allMembers
      .where((m) =>
          m.$2 == HouseholdRole.renter || m.$2 == HouseholdRole.princess)
      .toList();

  if (!context.mounted) return;

  if (renters.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No Roomies or Princesses to assign rent to.')),
    );
    return;
  }

  final now = DateTime.now();
  final period = DateFormat('yyyy-MM').format(now);
  final amountCtrl = TextEditingController();
  (UserModel, HouseholdRole)? selectedMember;
  bool isRecurring = false;
  int recurringDay = now.day.clamp(1, 28);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => SingleChildScrollView(
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
              'Assign Rent — ${_periodFmt.format(now)}',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Member picker
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Member',
                border: OutlineInputBorder(),
              ),
              value: selectedMember?.$1.uid,
              items: renters
                  .map((m) => DropdownMenuItem(
                        value: m.$1.uid,
                        child: Text(m.$1.displayName),
                      ))
                  .toList(),
              onChanged: (uid) => setS(() {
                selectedMember =
                    renters.firstWhere((m) => m.$1.uid == uid);
              }),
            ),
            const SizedBox(height: 12),

            // Amount
            TextField(
              controller: amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Rent amount',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),

            // Recurring toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: isRecurring,
              title: const Text('🔁 Recurring monthly'),
              subtitle: isRecurring
                  ? Text('Repeats on day $recurringDay each month')
                  : const Text('One-time entry'),
              onChanged: (v) => setS(() => isRecurring = v),
            ),
            if (isRecurring) ...[
              Text('Day of month: $recurringDay',
                  style: Theme.of(ctx).textTheme.bodySmall),
              Slider(
                value: recurringDay.toDouble(),
                min: 1,
                max: 28,
                divisions: 27,
                label: 'Day $recurringDay',
                onChanged: (v) => setS(() => recurringDay = v.round()),
              ),
            ],
            const SizedBox(height: 16),

            FilledButton(
              onPressed: () async {
                final member = selectedMember;
                final amount = double.tryParse(amountCtrl.text);
                if (member == null || amount == null || amount <= 0) return;

                final entry = RentEntry(
                  id: const Uuid().v4(),
                  totalAmount: amount,
                  memberShares: {member.$1.uid: amount},
                  period: period,
                  createdById: currentUid,
                  createdAt: DateTime.now(),
                  isRecurring: isRecurring,
                  recurringDay: isRecurring ? recurringDay : null,
                  paidStatus: {},
                );
                await service.addRentEntry(householdId, entry);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
}
