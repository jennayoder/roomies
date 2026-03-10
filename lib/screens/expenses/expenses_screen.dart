import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/expense.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

final _currencyFmt = NumberFormat.currency(symbol: '\$');

/// Expenses tab — shows shared household expenses with split amounts.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return StreamBuilder(
      stream: auth.userProfileStream(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user?.householdId == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Expenses')),
            body: const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No household',
              subtitle: 'Join or create a household from the Home tab.',
            ),
          );
        }

        return _ExpensesContent(
          householdId: user!.householdId!,
          currentUid: auth.currentUser!.uid,
        );
      },
    );
  }
}

class _ExpensesContent extends StatelessWidget {
  final String householdId;
  final String currentUid;

  const _ExpensesContent({
    required this.householdId,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _showAddExpenseSheet(context, householdId, currentUid, service),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: StreamBuilder<List<Expense>>(
        stream: service.expensesStream(householdId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget(message: 'Loading expenses…');
          }

          final expenses = snapshot.data ?? [];
          if (expenses.isEmpty) {
            return const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No expenses yet',
              subtitle: 'Tap "Add Expense" to log a shared purchase.',
            );
          }

          // Split into unsettled and settled
          final unsettled =
              expenses.where((e) => !e.isSettled).toList();
          final settled = expenses.where((e) => e.isSettled).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (unsettled.isNotEmpty) ...[
                _sectionHeader(context, 'Outstanding'),
                const SizedBox(height: 8),
                ...unsettled.map((e) => _ExpenseCard(
                      expense: e,
                      currentUid: currentUid,
                      householdId: householdId,
                      service: service,
                    )),
              ],
              if (settled.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionHeader(context, 'Settled'),
                const SizedBox(height: 8),
                ...settled.map((e) => _ExpenseCard(
                      expense: e,
                      currentUid: currentUid,
                      householdId: householdId,
                      service: service,
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final Expense expense;
  final String currentUid;
  final String householdId;
  final FirestoreService service;

  const _ExpenseCard({
    required this.expense,
    required this.currentUid,
    required this.householdId,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isPayer = expense.paidById == currentUid;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.secondaryContainer,
          child: Icon(
            _categoryIcon(expense.category),
            color: colors.onSecondaryContainer,
          ),
        ),
        title: Text(expense.title),
        subtitle: Text(
          '${expense.category.label} · '
          '${expense.splitAmongIds.length} people · '
          '${_currencyFmt.format(expense.sharePerPerson)}/person',
          style: textTheme.bodySmall,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _currencyFmt.format(expense.amount),
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isPayer ? colors.primary : colors.onSurface,
              ),
            ),
            if (expense.isSettled)
              Text(
                'Settled',
                style: textTheme.labelSmall
                    ?.copyWith(color: colors.tertiary),
              )
            else if (isPayer)
              Text(
                'You paid',
                style: textTheme.labelSmall
                    ?.copyWith(color: colors.primary),
              ),
          ],
        ),
        onLongPress: expense.isSettled
            ? null
            : () => _showExpenseActions(context),
      ),
    );
  }

  void _showExpenseActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outlined),
              title: const Text('Mark as settled'),
              onTap: () {
                service.settleExpense(householdId, expense.id);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outlined,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(
                'Delete',
                style:
                    TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                service.deleteExpense(householdId, expense.id);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(ExpenseCategory cat) => switch (cat) {
        ExpenseCategory.groceries => Icons.shopping_cart_outlined,
        ExpenseCategory.utilities => Icons.bolt_outlined,
        ExpenseCategory.household => Icons.home_outlined,
        ExpenseCategory.entertainment => Icons.movie_outlined,
        ExpenseCategory.transport => Icons.directions_car_outlined,
        ExpenseCategory.other => Icons.attach_money,
      };
}

// ─── Add expense sheet ────────────────────────────────────────────────────────

Future<void> _showAddExpenseSheet(
  BuildContext context,
  String householdId,
  String currentUid,
  FirestoreService service,
) async {
  final titleCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  ExpenseCategory selectedCategory = ExpenseCategory.other;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
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
              'Add Expense',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ExpenseCategory>(
              value: selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: ExpenseCategory.values
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c.label),
                      ))
                  .toList(),
              onChanged: (v) => setS(() => selectedCategory = v!),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final amount = double.tryParse(amountCtrl.text);
                if (title.isEmpty || amount == null || amount <= 0) return;

                final expense = Expense(
                  id: const Uuid().v4(),
                  title: title,
                  amount: amount,
                  category: selectedCategory,
                  paidById: currentUid,
                  splitAmongIds: [currentUid], // simplified: split just with self for now
                  createdAt: DateTime.now(),
                );
                await service.addExpense(householdId, expense);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
}
