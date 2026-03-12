import 'package:cloud_firestore/cloud_firestore.dart';

/// A monthly rent record for the household.
///
/// Stored at: /households/{householdId}/rent/{rentEntryId}
class RentEntry {
  final String id;

  /// Total rent amount for the period (e.g. 3000.00).
  final double totalAmount;

  /// Each member's share: { uid: amount }.
  final Map<String, double> memberShares;

  /// ISO-8601 string for the billing period, e.g. '2024-03'.
  final String period;

  /// UID of the member who logged this entry.
  final String createdById;

  final DateTime createdAt;

  /// Whether all members have marked their share as paid.
  final bool isFullyPaid;

  /// Per-member paid status: { uid: true/false }
  final Map<String, bool> paidStatus;

  /// Whether this rent repeats monthly.
  final bool isRecurring;

  /// Day of month to auto-create next entry (1–28) if recurring.
  final int? recurringDay;

  const RentEntry({
    required this.id,
    required this.totalAmount,
    required this.memberShares,
    required this.period,
    required this.createdById,
    required this.createdAt,
    this.isFullyPaid = false,
    this.paidStatus = const {},
    this.isRecurring = false,
    this.recurringDay,
  });

  // ─── Firestore serialization ───────────────────────────────────────────────

  factory RentEntry.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RentEntry(
      id: doc.id,
      totalAmount: (data['totalAmount'] as num).toDouble(),
      memberShares: Map<String, double>.from(
        (data['memberShares'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      ),
      period: data['period'] as String,
      createdById: data['createdById'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isFullyPaid: (data['isFullyPaid'] as bool?) ?? false,
      paidStatus: data['paidStatus'] != null
          ? Map<String, bool>.from(
              (data['paidStatus'] as Map).map(
                (k, v) => MapEntry(k as String, v as bool),
              ),
            )
          : {},
      isRecurring: (data['isRecurring'] as bool?) ?? false,
      recurringDay: data['recurringDay'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
        'totalAmount': totalAmount,
        'memberShares': memberShares,
        'period': period,
        'createdById': createdById,
        'createdAt': Timestamp.fromDate(createdAt),
        'isFullyPaid': isFullyPaid,
        'paidStatus': paidStatus,
        'isRecurring': isRecurring,
        'recurringDay': recurringDay,
      };
}
