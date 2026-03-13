import 'package:cloud_firestore/cloud_firestore.dart';

enum ExpenseCategory {
  groceries,
  utilities,
  household,
  entertainment,
  transport,
  other,
}

extension ExpenseCategoryLabel on ExpenseCategory {
  String get label => switch (this) {
        ExpenseCategory.groceries => 'Groceries',
        ExpenseCategory.utilities => 'Utilities',
        ExpenseCategory.household => 'Household',
        ExpenseCategory.entertainment => 'Entertainment',
        ExpenseCategory.transport => 'Transport',
        ExpenseCategory.other => 'Other',
      };
}

/// A shared expense logged by a household member.
///
/// Stored at: /households/{householdId}/expenses/{expenseId}
class Expense {
  final String id;
  final String title;

  /// Total expense amount.
  final double amount;

  final ExpenseCategory category;

  /// UID of the member who paid/fronted the expense.
  final String paidById;

  /// Per-member amounts owed: { uid: amount }.
  /// Members not in this map don't owe anything.
  final Map<String, double> memberAmounts;

  /// Per-member paid status: { uid: true/false }.
  final Map<String, bool> paidStatus;

  final DateTime createdAt;

  /// True when all members in memberAmounts have paid.
  final bool isSettled;

  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.paidById,
    required this.memberAmounts,
    this.paidStatus = const {},
    required this.createdAt,
    this.isSettled = false,
  });

  /// Legacy: keep splitAmongIds derived from memberAmounts keys.
  List<String> get splitAmongIds => memberAmounts.keys.toList();

  factory Expense.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Support both old splitAmongIds + amount and new memberAmounts
    Map<String, double> memberAmounts;
    if (data['memberAmounts'] != null) {
      memberAmounts = Map<String, double>.from(
        (data['memberAmounts'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      );
    } else {
      // Legacy: equal split
      final ids = List<String>.from(data['splitAmongIds'] as List? ?? []);
      final total = (data['amount'] as num).toDouble();
      final share = ids.isEmpty ? total : total / ids.length;
      memberAmounts = {for (final id in ids) id: share};
    }

    return Expense(
      id: doc.id,
      title: data['title'] as String,
      amount: (data['amount'] as num).toDouble(),
      category: ExpenseCategory.values.firstWhere(
        (e) => e.name == data['category'],
        orElse: () => ExpenseCategory.other,
      ),
      paidById: data['paidById'] as String,
      memberAmounts: memberAmounts,
      paidStatus: data['paidStatus'] != null
          ? Map<String, bool>.from(
              (data['paidStatus'] as Map).map(
                (k, v) => MapEntry(k as String, v as bool),
              ),
            )
          : {},
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isSettled: (data['isSettled'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'amount': amount,
        'category': category.name,
        'paidById': paidById,
        'memberAmounts': memberAmounts,
        'splitAmongIds': splitAmongIds, // legacy compat
        'paidStatus': paidStatus,
        'createdAt': Timestamp.fromDate(createdAt),
        'isSettled': isSettled,
      };
}
