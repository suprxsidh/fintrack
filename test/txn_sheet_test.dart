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

  testWidgets(
      'Add with blank merchant shows visible feedback and does not save',
      (tester) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () =>
                  showTxnSheet(context, ref, prefillPaise: 5500),
              child: const Text('open'),
            );
          }),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add transaction'), findsOneWidget);

    // Amount is prefilled; merchant is left blank (as it always is when
    // opened from the review queue before bug-B's _guessMerchant fix).
    // The button is below the fold in the test surface, so scroll it into
    // view before tapping.
    await tester.ensureVisible(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pump();

    // Sheet is still open — nothing was saved.
    expect(find.text('Add transaction'), findsOneWidget);
    expect(await db.select(db.transactions).get(), isEmpty);
    // Visible feedback appeared.
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Add with amount and merchant filled in saves and closes',
      (tester) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () => showTxnSheet(context, ref,
                  prefillPaise: 5500, prefillMerchant: 'CHOWRASIA CHATS'),
              child: const Text('open'),
            );
          }),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add transaction'), findsOneWidget);

    await tester.ensureVisible(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final saved = await db.select(db.transactions).get();
    expect(saved, hasLength(1));
    expect(saved.single.amountPaise, 5500);
    expect(saved.single.merchant, 'CHOWRASIA CHATS');
    expect(find.text('Add transaction'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
