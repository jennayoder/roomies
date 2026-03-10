import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/rent_entry.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

final _currencyFmt = NumberFormat.currency(symbol: '\$');

/// Rent tab — lists monthly rent entries and allows logging new ones.
class RentScreen extends StatelessWidget {
  const RentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return StreamBuilder(
      stream: auth.userProfileStream(),
      builder: (context, snapshot) {
        final user = snapshot.data;
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

        return _RentContent(householdId: user!.householdId!);
      },
    );
  }
}

class _RentContent extends StatelessWidget {
  final String householdId;
  const _RentContent({required this.householdId});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text('Rent')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRentDialog(context, householdId, service),
        icon: const Icon(Icons.add),
        label: const Text('Log Rent'),
      ),
      body: StreamBuilder<List<RentEntry>>(
        stream: service.rentStream(householdId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget(message: 'Loading rent entries…');
          }

          final entries = snapshot.data ?? [];
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No rent entries yet',
              subtitle: 'Tap "Log Rent" to record this month\'s rent.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final entry = entries[i];
              return _RentEntryCard(
                entry: entry,
                householdId: householdId,
                service: service,
              );
            },
          );
        },
      ),
    );
  }
}

class _RentEntryCard extends StatelessWidget {
  final RentEntry entry;
  final String householdId;
  final FirestoreService service;

  const _RentEntryCard({
    required this.entry,
    required this.householdId,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.period,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (entry.isFullyPaid)
                  Chip(
                    label: const Text('Paid'),
                    avatar: const Icon(Icons.check_circle, size: 16),
                    backgroundColor: colors.tertiaryContainer,
                    labelStyle:
                        TextStyle(color: colors.onTertiaryContainer),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () =>
                        service.markRentPaid(householdId, entry.id),
                    child: const Text('Mark Paid'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Total: ${_currencyFmt.format(entry.totalAmount)}',
              style: textTheme.bodyLarge,
            ),
            const Divider(height: 20),
            Text(
              'Member shares:',
              style: textTheme.labelMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            ...entry.memberShares.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key, style: textTheme.bodySmall),
                    Text(
                      _currencyFmt.format(e.value),
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add rent dialog ──────────────────────────────────────────────────────────

Future<void> _showAddRentDialog(
  BuildContext context,
  String householdId,
  FirestoreService service,
) async {
  final amountCtrl = TextEditingController();
  final now = DateTime.now();
  final period = DateFormat('yyyy-MM').format(now);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
            'Log Rent — $period',
            style: Theme.of(ctx).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Total rent amount',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text);
              if (amount == null || amount <= 0) return;

              final auth = context.read<AuthService>();
              final uid = auth.currentUser!.uid;

              final entry = RentEntry(
                id: const Uuid().v4(),
                totalAmount: amount,
                memberShares: {uid: amount}, // simplified single-payer
                period: period,
                createdById: uid,
                createdAt: DateTime.now(),
              );
              await service.addRentEntry(householdId, entry);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
