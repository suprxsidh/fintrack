import 'package:drift/drift.dart';

import 'db.dart';

/// Dedup window: two SMS for the same amount+account this close together are
/// the same transaction (banks often double-send).
const dedupWindow = Duration(seconds: 90);

extension TransactionDao on AppDb {
  Future<int> insertTransaction(TransactionsCompanion txn) =>
      into(transactions).insert(txn);

  /// True if a matching smsRef exists, or same amount+accountTail within
  /// [dedupWindow] of [txDate].
  Future<bool> isDuplicate({
    required int amountPaise,
    String? accountTail,
    String? smsRef,
    required DateTime txDate,
  }) async {
    if (smsRef != null) {
      final byRef = await (select(transactions)
            ..where((t) => t.smsRef.equals(smsRef)))
          .get();
      if (byRef.isNotEmpty) return true;
    }
    final lo = txDate.subtract(dedupWindow);
    final hi = txDate.add(dedupWindow);
    final near = await (select(transactions)
          ..where((t) =>
              t.amountPaise.equals(amountPaise) &
              t.txDate.isBetweenValues(lo, hi) &
              (accountTail == null
                  ? t.accountTail.isNull()
                  : t.accountTail.equals(accountTail))))
        .get();
    return near.isNotEmpty;
  }

  /// All transactions in [month]'s calendar month, newest first. Same-day
  /// rows (common: bank SMS often carry no time-of-day) break ties by
  /// createdAt so the most recently captured shows first.
  Future<List<Transaction>> monthTransactions(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return (select(transactions)
          ..where((t) =>
              t.txDate.isBiggerOrEqualValue(start) &
              t.txDate.isSmallerThanValue(end))
          ..orderBy([
            (t) => OrderingTerm.desc(t.txDate),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
  }

  /// Debit paise per categoryId (null key = uncategorized) for the month.
  Future<Map<int?, int>> spendByCategory(DateTime month) async {
    final txns = await monthTransactions(month);
    final out = <int?, int>{};
    for (final t in txns.where((t) => t.direction == TxnDirection.debit)) {
      out[t.categoryId] = (out[t.categoryId] ?? 0) + t.amountPaise;
    }
    return out;
  }

  /// Sets the category and teaches merchant memory.
  Future<void> setCategory(int txId, int catId) async {
    final txn = await (select(transactions)..where((t) => t.id.equals(txId)))
        .getSingle();
    await (update(transactions)..where((t) => t.id.equals(txId)))
        .write(TransactionsCompanion(categoryId: Value(catId)));
    await into(merchantMemory).insertOnConflictUpdate(
        MerchantMemoryCompanion.insert(
            merchant: txn.merchant.toUpperCase(), categoryId: catId));
  }

  /// Remembered category for a merchant, if any.
  Future<int?> categoryFor(String merchant) async {
    final row = await (select(merchantMemory)
          ..where((m) => m.merchant.equals(merchant.toUpperCase())))
        .getSingleOrNull();
    return row?.categoryId;
  }

  Future<List<Category>> allCategories() => select(categories).get();
}
