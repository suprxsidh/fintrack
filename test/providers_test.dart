import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fintrack/data/daos.dart';
import 'package:fintrack/data/db.dart';
import 'package:fintrack/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('monthTxnsProvider orders same-day rows by createdAt, newest first',
      () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    final sameDay = DateTime(now.year, now.month, now.day);
    final firstId = await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 100,
      direction: TxnDirection.debit,
      merchant: 'FIRST',
      txDate: sameDay,
      source: TxnSource.sms,
      createdAt: Value(sameDay.add(const Duration(hours: 1))),
    ));
    final secondId = await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 200,
      direction: TxnDirection.debit,
      merchant: 'SECOND',
      txDate: sameDay,
      source: TxnSource.sms,
      createdAt: Value(sameDay.add(const Duration(hours: 2))),
    ));

    final container =
        ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);

    // Riverpod 3 disposes a StreamProvider mid-load if nothing is keeping it
    // alive; an explicit listener keeps the underlying stream subscription
    // open while we await the first emission via `.future`.
    final sub = container.listen(monthTxnsProvider, (_, __) {});
    addTearDown(sub.close);

    final txns = await container.read(monthTxnsProvider.future);
    expect(txns.map((t) => t.id).toList(), [secondId, firstId]);
  });
}
