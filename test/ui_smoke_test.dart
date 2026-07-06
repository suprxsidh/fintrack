import 'package:drift/native.dart';
import 'package:fintrack/data/daos.dart';
import 'package:fintrack/data/db.dart';
import 'package:fintrack/state/providers.dart';
import 'package:fintrack/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots, home renders, tabs switch', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 5500,
      direction: TxnDirection.debit,
      merchant: 'PRAVEEN R V',
      txDate: DateTime.now(),
      source: TxnSource.sms,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const FinTrackApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Spent this month'), findsOneWidget);
    expect(find.text('PRAVEEN R V'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets); // search box

    // manual add sheet opens
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Add transaction'), findsOneWidget);

    // dispose the whole tree before teardown so no widget/provider timers
    // (cursor blink, riverpod retry) survive to trip the pending-timer check
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
