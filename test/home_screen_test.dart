import 'package:drift/native.dart';
import 'package:fintrack/data/daos.dart';
import 'package:fintrack/data/db.dart';
import 'package:fintrack/state/providers.dart';
import 'package:fintrack/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('swiping a Recent transaction on Home deletes it with Undo',
      (tester) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 5500,
      direction: TxnDirection.debit,
      merchant: 'RAMESH KUMAR',
      txDate: DateTime.now(),
      source: TxnSource.sms,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const MaterialApp(home: Scaffold(body: HomeScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('RAMESH KUMAR'), findsOneWidget);

    await tester.drag(find.text('RAMESH KUMAR'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('RAMESH KUMAR'), findsNothing);
    expect(find.text('Deleted RAMESH KUMAR'), findsOneWidget);

    // dispose before teardown, matching ui_smoke_test.dart's pattern
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
