import '../data/db.dart';

class RecurringSuggestion {
  final String merchant;
  final int amountPaise;
  final int dueDay;
  final int occurrences;

  const RecurringSuggestion({
    required this.merchant,
    required this.amountPaise,
    required this.dueDay,
    required this.occurrences,
  });
}

/// Flags merchants that charge the same amount on a ~monthly cadence
/// (28–32 day gaps, at least 2 gaps ≈ 3 hits, tolerating one-off misses).
class RecurringDetector {
  static List<RecurringSuggestion> suggest(
    List<Transaction> txns, {
    Set<String> alreadyTracked = const {},
  }) {
    final byKey = <String, List<Transaction>>{};
    for (final t in txns.where((t) => t.direction == TxnDirection.debit)) {
      byKey
          .putIfAbsent('${t.merchant.toUpperCase()}|${t.amountPaise}', () => [])
          .add(t);
    }
    final out = <RecurringSuggestion>[];
    byKey.forEach((key, list) {
      final merchant = list.first.merchant;
      if (alreadyTracked.contains(merchant.toUpperCase())) return;
      if (list.length < 2) return;
      list.sort((a, b) => a.txDate.compareTo(b.txDate));
      var monthlyGaps = 0;
      for (var i = 1; i < list.length; i++) {
        final gap = list[i].txDate.difference(list[i - 1].txDate).inDays;
        if (gap >= 28 && gap <= 32) monthlyGaps++;
      }
      if (monthlyGaps >= 1 && list.length >= 2) {
        out.add(RecurringSuggestion(
          merchant: merchant,
          amountPaise: list.first.amountPaise,
          dueDay: list.last.txDate.day,
          occurrences: list.length,
        ));
      }
    });
    out.sort((a, b) => b.occurrences.compareTo(a.occurrences));
    return out;
  }
}
