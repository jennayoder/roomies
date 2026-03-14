import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/expense.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

final _currencyFmt = NumberFormat.currency(symbol: '\$');

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return StreamBuilder<UserModel?>(
      stream: auth.userProfileStream(),
      builder: (context, snap) {
        final user = snap.data;
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

enum _ExpenseFilter { all, mine }

class _ExpensesContent extends StatefulWidget {
  final String householdId;
  final String currentUid;
  const _ExpensesContent(
      {required this.householdId, required this.currentUid});

  @override
  State<_ExpensesContent> createState() => _ExpensesContentState();
}

class _ExpensesContentState extends State<_ExpensesContent> {
  _ExpenseFilter _filter = _ExpenseFilter.all;

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddExpenseSheet(
            context, widget.householdId, widget.currentUid, service),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: StreamBuilder<List<Expense>>(
        stream: service.expensesStream(widget.householdId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingWidget(message: 'Loading expenses…');
          }

          final all = snap.data ?? [];

          // Apply filter
          final filtered = _filter == _ExpenseFilter.mine
              ? all
                  .where((e) =>
                      e.memberAmounts.containsKey(widget.currentUid) ||
                      e.paidById == widget.currentUid)
                  .toList()
              : all;

          // Split: unpaid on top, fully settled on bottom
          final unpaid = filtered.where((e) => !e.isSettled).toList();
          final settled = filtered.where((e) => e.isSettled).toList();

          // Within unpaid, surface ones where current user still owes first
          unpaid.sort((a, b) {
            final aOwes = a.memberAmounts.containsKey(widget.currentUid) &&
                !(a.paidStatus[widget.currentUid] ?? false);
            final bOwes = b.memberAmounts.containsKey(widget.currentUid) &&
                !(b.paidStatus[widget.currentUid] ?? false);
            if (aOwes && !bOwes) return -1;
            if (!aOwes && bOwes) return 1;
            return b.createdAt.compareTo(a.createdAt); // newest first otherwise
          });

          // Settled: newest first
          settled.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return Column(
            children: [
              // ── Filter chips ──────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _filter == _ExpenseFilter.all,
                      onSelected: (_) =>
                          setState(() => _filter = _ExpenseFilter.all),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Mine'),
                      selected: _filter == _ExpenseFilter.mine,
                      onSelected: (_) =>
                          setState(() => _filter = _ExpenseFilter.mine),
                    ),
                    const Spacer(),
                    if (filtered.isNotEmpty)
                      Text(
                        '${filtered.length} expense${filtered.length == 1 ? '' : 's'}',
                        style: textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                  ],
                ),
              ),

              // ── List ──────────────────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.account_balance_wallet_outlined,
                        title: _filter == _ExpenseFilter.mine
                            ? 'No expenses involve you'
                            : 'No expenses yet',
                        subtitle: _filter == _ExpenseFilter.mine
                            ? 'Switch to "All" to see the full list.'
                            : 'Tap "Add Expense" to log a shared purchase.',
                      )
                    : ListView(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        children: [
                          if (unpaid.isNotEmpty) ...[
                            _sectionHeader(context, 'Unpaid'),
                            const SizedBox(height: 8),
                            ...unpaid.map((e) => _ExpenseCard(
                                  expense: e,
                                  currentUid: widget.currentUid,
                                  householdId: widget.householdId,
                                  service: service,
                                )),
                          ],
                          if (settled.isNotEmpty) ...[
                            if (unpaid.isNotEmpty) const SizedBox(height: 16),
                            _sectionHeader(context, 'Paid'),
                            const SizedBox(height: 8),
                            ...settled.map((e) => _ExpenseCard(
                                  expense: e,
                                  currentUid: widget.currentUid,
                                  householdId: widget.householdId,
                                  service: service,
                                )),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

// ─── Expense card ─────────────────────────────────────────────────────────────

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
    final myAmount = expense.memberAmounts[currentUid];
    final iHavePaid = expense.paidStatus[currentUid] ?? false;
    final iOwe = myAmount != null && !iHavePaid;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showExpenseDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colors.secondaryContainer,
                    child: Icon(_categoryIcon(expense.category),
                        color: colors.onSecondaryContainer, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(expense.title,
                            style: textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(
                          '${expense.category.label} · ${expense.memberAmounts.length} member${expense.memberAmounts.length == 1 ? '' : 's'}',
                          style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _currencyFmt.format(expense.amount),
                        style: textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (expense.isSettled)
                        Text('Settled ✅',
                            style: textTheme.labelSmall
                                ?.copyWith(color: colors.primary))
                      else if (iOwe)
                        Text(
                          'You owe ${_currencyFmt.format(myAmount)}',
                          style: textTheme.labelSmall
                              ?.copyWith(color: colors.error),
                        )
                      else if (iHavePaid)
                        Text('You paid ✅',
                            style: textTheme.labelSmall
                                ?.copyWith(color: colors.primary)),
                    ],
                  ),
                ],
              ),

              // Pay button if current user owes
              if (iOwe) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => service.markExpenseMemberPaid(
                        householdId, expense.id, currentUid),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                        'Mark My Share Paid (${_currencyFmt.format(myAmount)})'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showExpenseDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ExpenseDetailSheet(
        expense: expense,
        householdId: householdId,
        currentUid: currentUid,
        service: service,
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

// ─── Expense detail sheet ─────────────────────────────────────────────────────

class _ExpenseDetailSheet extends StatelessWidget {
  final Expense expense;
  final String householdId;
  final String currentUid;
  final FirestoreService service;

  const _ExpenseDetailSheet({
    required this.expense,
    required this.householdId,
    required this.currentUid,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colors.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(expense.title,
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              if (expense.isSettled)
                Chip(
                  label: const Text('Settled ✅'),
                  backgroundColor: colors.tertiaryContainer,
                  labelStyle: TextStyle(color: colors.onTertiaryContainer),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${expense.category.label} · Total: ${_currencyFmt.format(expense.amount)}',
            style: textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const Divider(height: 24),

          // Per-member breakdown
          Text('Who owes what',
              style: textTheme.labelMedium
                  ?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          ...expense.memberAmounts.entries.map((e) {
            final paid = expense.paidStatus[e.key] ?? false;
            final isMe = e.key == currentUid;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    paid ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 18,
                    color: paid ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MemberName(uid: e.key, householdId: householdId,
                        suffix: isMe ? ' (you)' : null),
                  ),
                  Text(_currencyFmt.format(e.value),
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: paid ? colors.primary : null,
                        decoration: paid ? TextDecoration.lineThrough : null,
                      )),
                  if (!paid) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        await service.markExpenseMemberPaid(
                            householdId, expense.id, e.key);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Mark Paid'),
                    ),
                  ],
                ],
              ),
            );
          }),

          // Delete
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error),
            ),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dCtx) => AlertDialog(
                  title: const Text('Delete expense?'),
                  content: const Text('This will permanently remove this expense.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: colors.error),
                      onPressed: () => Navigator.pop(dCtx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await service.deleteExpense(householdId, expense.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete Expense'),
          ),
        ],
      ),
    );
  }
}

// ─── Member name widget ───────────────────────────────────────────────────────

class _MemberName extends StatefulWidget {
  final String uid;
  final String householdId;
  final String? suffix;
  const _MemberName(
      {required this.uid, required this.householdId, this.suffix});

  @override
  State<_MemberName> createState() => _MemberNameState();
}

class _MemberNameState extends State<_MemberName> {
  String _name = '…';

  @override
  void initState() {
    super.initState();
    FirestoreService().getHouseholdMembers(widget.householdId).then((ms) {
      final match = ms.where((m) => m.$1.uid == widget.uid).firstOrNull;
      if (match != null && mounted) {
        setState(() => _name = match.$1.displayName + (widget.suffix ?? ''));
      }
    });
  }

  @override
  Widget build(BuildContext context) => Text(_name);
}

// ─── Add expense sheet ────────────────────────────────────────────────────────

Future<void> _showAddExpenseSheet(
  BuildContext context,
  String householdId,
  String currentUid,
  FirestoreService service,
) async {
  // Fetch all members
  final allMembers = await FirestoreService().getHouseholdMembers(householdId);
  if (!context.mounted) return;

  final titleCtrl = TextEditingController();
  ExpenseCategory selectedCategory = ExpenseCategory.other;

  // Per-member checkboxes + amount controllers
  final selectedMembers = <String, bool>{
    for (final m in allMembers) m.$1.uid: false,
  };
  final amountCtrls = <String, TextEditingController>{
    for (final m in allMembers) m.$1.uid: TextEditingController(),
  };

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add Expense', style: Theme.of(ctx).textTheme.titleLarge),
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

            DropdownButtonFormField<ExpenseCategory>(
              value: selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: ExpenseCategory.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                  .toList(),
              onChanged: (v) => setS(() => selectedCategory = v!),
            ),
            const SizedBox(height: 16),

            Text('Who owes? (check + enter amount)',
                style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),

            // Checkbox + amount per member
            ...allMembers.map((m) {
              final uid = m.$1.uid;
              final isChecked = selectedMembers[uid] ?? false;
              final name = uid == currentUid
                  ? '${m.$1.displayName} (you)'
                  : m.$1.displayName;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: isChecked,
                      onChanged: (v) =>
                          setS(() => selectedMembers[uid] = v ?? false),
                    ),
                    Expanded(child: Text(name)),
                    if (isChecked)
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: amountCtrls[uid],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            prefixText: '\$ ',
                            hintText: '0.00',
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 10),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;

                final memberAmounts = <String, double>{};
                for (final m in allMembers) {
                  if (selectedMembers[m.$1.uid] == true) {
                    final amt =
                        double.tryParse(amountCtrls[m.$1.uid]?.text ?? '');
                    if (amt != null && amt > 0) {
                      memberAmounts[m.$1.uid] = amt;
                    }
                  }
                }
                if (memberAmounts.isEmpty) return;

                final total =
                    memberAmounts.values.fold(0.0, (a, b) => a + b);
                final expense = Expense(
                  id: const Uuid().v4(),
                  title: title,
                  amount: total,
                  category: selectedCategory,
                  paidById: currentUid,
                  memberAmounts: memberAmounts,
                  paidStatus: {},
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
