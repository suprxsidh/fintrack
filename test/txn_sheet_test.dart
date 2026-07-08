import 'package:drift/native.dart';
import 'package:fintrack/data/daos.dart';
import 'package:fintrack/data/db.dart';
import 'package:fintrack/state/providers.dart';
import 'package:fintrack/ui/txn_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('delete button in edit sheet removes the transaction',
      (tester) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 5500,
      direction: TxnDirection.debit,
      merchant: 'RAMESH KUMAR',
      txDate: DateTime.now(),
      source: TxnSource.sms,
    ));
    final existing = await (db.select(db.transactions)
          ..where((t) => t.id.equals(id)))
        .getSingle();

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () => showTxnSheet(context, ref, existing: existing),
              child: const Text('open'),
            );
          }),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit transaction'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete transaction?'), findsOneWidget);

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(await db.select(db.transactions).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
