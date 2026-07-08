import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fintrack/data/daos.dart';
import 'package:fintrack/data/db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('monthTxnsProvider ordering test - same-day by createdAt descending',
      () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);

    final sameDay = DateTime(2026, 7, 6);
    final firstId = await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 100,
      direction: TxnDirection.debit,
      merchant: 'FIRST',
      txDate: sameDay,
      source: TxnSource.sms,
      createdAt: Value(DateTime(2026, 7, 6, 10, 0)),
    ));
    final secondId = await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 200,
      direction: TxnDirection.debit,
      merchant: 'SECOND',
      txDate: sameDay,
      source: TxnSource.sms,
      createdAt: Value(DateTime(2026, 7, 6, 11, 0)),
    ));

    final txns = await db.monthTransactions(DateTime(2026, 7));
    expect(txns.map((t) => t.id).toList(), [secondId, firstId],
        reason: 'must order by createdAt DESC for same-day transactions');
  });
}
