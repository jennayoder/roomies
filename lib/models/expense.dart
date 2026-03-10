import 'package:cloud_firestore/cloud_firestore.dart';

/// Categories for shared household expenses.
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
  final double amount;
  final ExpenseCategory category;

  /// UID of the member who paid for the expense.
  final String paidById;

  /// UIDs of members who should share this expense.
  final List<String> splitAmongIds;

  final DateTime createdAt;

  /// Whether this expense has been settled among all members.
  final bool isSettled;

  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.paidById,
    required this.splitAmongIds,
    required this.createdAt,
    this.isSettled = false,
  });

  /// The per-person share for this expense.
  double get sharePerPerson =>
      splitAmongIds.isEmpty ? 0 : amount / splitAmongIds.length;

  // ─── Firestore serialization ───────────────────────────────────────────────

  factory Expense.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Expense(
      id: doc.id,
      title: data['title'] as String,
      amount: (data['amount'] as num).toDouble(),
      category: ExpenseCategory.values.firstWhere(
        (e) => e.name == data['category'],
        orElse: () => ExpenseCategory.other,
      ),
      paidById: data['paidById'] as String,
      splitAmongIds: List<String>.from(data['splitAmongIds'] as List),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isSettled: (data['isSettled'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'amount': amount,
        'category': category.name,
        'paidById': paidById,
        'splitAmongIds': splitAmongIds,
        'createdAt': Timestamp.fromDate(createdAt),
        'isSettled': isSettled,
      };
}
