import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/db.dart';

/// Overridden with the real DB in main().
final dbProvider = Provider<AppDb>((ref) => throw UnimplementedError());

final selectedMonthProvider = StateProvider<DateTime>((_) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final categoriesProvider = StreamProvider<List<Category>>(
    (ref) => ref.watch(dbProvider).select(ref.watch(dbProvider).categories).watch());

/// Quick lookup: categoryId → Category.
final categoryMapProvider = Provider<Map<int, Category>>((ref) {
  final cats = ref.watch(categoriesProvider).value ?? const [];
  return {for (final c in cats) c.id: c};
});

final monthTxnsProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(dbProvider);
  final month = ref.watch(selectedMonthProvider);
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  return (db.select(db.transactions)
        ..where((t) =>
            t.txDate.isBiggerOrEqualValue(start) &
            t.txDate.isSmallerThanValue(end))
        ..orderBy([(t) => OrderingTerm.desc(t.txDate)]))
      .watch();
});

/// Debit paise by categoryId for the selected month (null = uncategorized).
final monthSpendByCategoryProvider = Provider<Map<int?, int>>((ref) {
  final txns = ref.watch(monthTxnsProvider).value ?? const [];
  final out = <int?, int>{};
  for (final t in txns.where((t) => t.direction == TxnDirection.debit)) {
    out[t.categoryId] = (out[t.categoryId] ?? 0) + t.amountPaise;
  }
  return out;
});

final monthSpentProvider = Provider<int>((ref) => ref
    .watch(monthSpendByCategoryProvider)
    .values
    .fold(0, (a, b) => a + b));

final budgetsProvider = StreamProvider<List<Budget>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.budgets)..where((b) => b.active.equals(true))).watch();
});

final recurringRulesProvider = StreamProvider<List<RecurringRule>>(
    (ref) => ref.watch(dbProvider).select(ref.watch(dbProvider).recurringRules).watch());

final reviewQueueProvider = StreamProvider<List<ReviewQueueData>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.reviewQueue)..where((r) => r.resolved.equals(false)))
      .watch();
});

/// Last ~6 months of transactions, for trend charts + recurring detection.
final recentTxnsProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(dbProvider);
  final cutoff = DateTime.now().subtract(const Duration(days: 185));
  return (db.select(db.transactions)
        ..where((t) => t.txDate.isBiggerOrEqualValue(cutoff))
        ..orderBy([(t) => OrderingTerm.asc(t.txDate)]))
      .watch();
});
