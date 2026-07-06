import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fintrack/data/daos.dart';
import 'package:fintrack/data/db.dart';
import 'package:fintrack/services/csv_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('csv roundtrip: export → import into fresh db → same data', () async {
    final a = AppDb(NativeDatabase.memory());
    final idA = await a.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 5500,
      direction: TxnDirection.debit,
      merchant: 'PRAVEEN R V',
      accountTail: const Value('106'),
      txDate: DateTime(2026, 7, 6),
      source: TxnSource.sms,
      note: const Value('lunch'),
    ));
    await a.setCategory(idA, 1); // Food
    await a.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 200000,
      direction: TxnDirection.credit,
      merchant: 'FRIEND',
      txDate: DateTime(2026, 7, 2),
      source: TxnSource.manual,
    ));

    final csv = await CsvService(a).export();
    expect(csv.split('\n').length, 3); // header + 2 rows

    final b = AppDb(NativeDatabase.memory());
    final (added, skipped) = await CsvService(b).import(csv);
    expect(added, 2);
    expect(skipped, 0);

    final rows = await b.monthTransactions(DateTime(2026, 7));
    expect(rows.length, 2);
    final lunch = rows.firstWhere((t) => t.merchant == 'PRAVEEN R V');
    expect(lunch.amountPaise, 5500);
    expect(lunch.note, 'lunch');
    expect(lunch.accountTail, '106');
    final cats = await b.allCategories();
    expect(cats.firstWhere((c) => c.id == lunch.categoryId).name, 'Food');

    // re-import is a no-op
    final (added2, skipped2) = await CsvService(b).import(csv);
    expect(added2, 0);
    expect(skipped2, 2);

    await a.close();
    await b.close();
  });

  test('import creates unknown categories', () async {
    final db = AppDb(NativeDatabase.memory());
    const csv = 'date,amount,direction,merchant,category,account,note,source\n'
        '2026-07-01,99.00,debit,STEAM,Gaming,,,manual';
    final (added, _) = await CsvService(db).import(csv);
    expect(added, 1);
    final cats = await db.allCategories();
    expect(cats.map((c) => c.name), contains('Gaming'));
    await db.close();
  });
}
