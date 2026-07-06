import 'package:fintrack/data/db.dart';
import 'package:fintrack/services/recurring_detector.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction txn(String merchant, int paise, DateTime date,
        {TxnDirection dir = TxnDirection.debit}) =>
    Transaction(
      id: date.millisecondsSinceEpoch ~/ 1000,
      amountPaise: paise,
      direction: dir,
      merchant: merchant,
      txDate: date,
      source: TxnSource.sms,
      createdAt: date,
    );

void main() {
  test('detects monthly same-amount merchant', () {
    final txns = [
      txn('SPOTIFY', 11900, DateTime(2026, 4, 5)),
      txn('SPOTIFY', 11900, DateTime(2026, 5, 5)),
      txn('SPOTIFY', 11900, DateTime(2026, 6, 4)),
      txn('SWIGGY', 25000, DateTime(2026, 6, 1)), // one-off
    ];
    final s = RecurringDetector.suggest(txns);
    expect(s.length, 1);
    expect(s.single.merchant, 'SPOTIFY');
    expect(s.single.amountPaise, 11900);
    expect(s.single.dueDay, 4);
    expect(s.single.occurrences, 3);
  });

  test('same merchant different amounts not merged', () {
    final txns = [
      txn('SWIGGY', 25000, DateTime(2026, 5, 5)),
      txn('SWIGGY', 31000, DateTime(2026, 6, 5)),
    ];
    expect(RecurringDetector.suggest(txns), isEmpty);
  });

  test('non-monthly cadence ignored', () {
    final txns = [
      txn('METRO', 5000, DateTime(2026, 6, 1)),
      txn('METRO', 5000, DateTime(2026, 6, 8)),
      txn('METRO', 5000, DateTime(2026, 6, 15)),
    ];
    expect(RecurringDetector.suggest(txns), isEmpty);
  });

  test('already tracked merchants excluded', () {
    final txns = [
      txn('SPOTIFY', 11900, DateTime(2026, 5, 5)),
      txn('SPOTIFY', 11900, DateTime(2026, 6, 5)),
    ];
    expect(
        RecurringDetector.suggest(txns, alreadyTracked: {'SPOTIFY'}), isEmpty);
  });

  test('credits ignored', () {
    final txns = [
      txn('EMPLOYER', 500000, DateTime(2026, 5, 1), dir: TxnDirection.credit),
      txn('EMPLOYER', 500000, DateTime(2026, 6, 1), dir: TxnDirection.credit),
    ];
    expect(RecurringDetector.suggest(txns), isEmpty);
  });
}
