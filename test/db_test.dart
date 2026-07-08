import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:fintrack/data/daos.dart';
import 'package:fintrack/data/db.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionsCompanion txn({
  int amountPaise = 5500,
  String merchant = 'RAMESH KUMAR',
  String? accountTail = '123',
  String? smsRef,
  DateTime? txDate,
  TxnSource source = TxnSource.sms,
}) =>
    TransactionsCompanion.insert(
      amountPaise: amountPaise,
      direction: TxnDirection.debit,
      merchant: merchant,
      accountTail: Value(accountTail),
      txDate: txDate ?? DateTime(2026, 7, 6, 12, 0),
      source: source,
      smsRef: Value(smsRef),
    );

void main() {
  late AppDb db;
  setUp(() => db = AppDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('seed categories exist after create', () async {
    final cats = await db.allCategories();
    expect(cats.length, 9);
    expect(cats.map((c) => c.name), contains('Food'));
  });

  test('insert + fetch roundtrip in month query', () async {
    await db.insertTransaction(txn());
    final rows = await db.monthTransactions(DateTime(2026, 7));
    expect(rows.length, 1);
    expect(rows.first.amountPaise, 5500);
    expect(rows.first.direction, TxnDirection.debit);
    expect(await db.monthTransactions(DateTime(2026, 6)), isEmpty);
  });

  test('duplicate by smsRef', () async {
    await db.insertTransaction(txn(smsRef: '412345678901'));
    expect(
        await db.isDuplicate(
            amountPaise: 9900, // ref match wins regardless of amount
            smsRef: '412345678901',
            txDate: DateTime(2026, 7, 7)),
        isTrue);
  });

  test('duplicate by amount+account within 90s', () async {
    final t0 = DateTime(2026, 7, 6, 12, 0, 0);
    await db.insertTransaction(txn(txDate: t0));
    expect(
        await db.isDuplicate(
            amountPaise: 5500,
            accountTail: '123',
            txDate: t0.add(const Duration(seconds: 60))),
        isTrue);
    expect(
        await db.isDuplicate(
            amountPaise: 5500,
            accountTail: '123',
            txDate: t0.add(const Duration(seconds: 200))),
        isFalse,
        reason: 'outside window');
    expect(
        await db.isDuplicate(
            amountPaise: 5500,
            accountTail: '999',
            txDate: t0.add(const Duration(seconds: 60))),
        isFalse,
        reason: 'different account');
  });

  test('monthTransactions orders same-day rows by createdAt, newest first',
      () async {
    final sameDay = DateTime(2026, 7, 6); // midnight: mimics date-only SMS
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
    final rows = await db.monthTransactions(DateTime(2026, 7));
    expect(rows.map((r) => r.id).toList(), [secondId, firstId]);
  });

  test('setCategory teaches merchant memory, categoryFor recalls', () async {
    final id = await db.insertTransaction(txn());
    await db.setCategory(id, 1);
    expect(await db.categoryFor('RAMESH KUMAR'), 1);
    expect(await db.categoryFor('ramesh kumar'), 1, reason: 'case-insensitive');
    expect(await db.categoryFor('UNKNOWN SHOP'), isNull);
  });

  test('spendByCategory sums debits only', () async {
    final id = await db.insertTransaction(txn(amountPaise: 1000));
    await db.setCategory(id, 2);
    await db.insertTransaction(txn(amountPaise: 500, merchant: 'X'));
    await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 99999,
      direction: TxnDirection.credit,
      merchant: 'SALARY',
      txDate: DateTime(2026, 7, 1),
      source: TxnSource.sms,
    ));
    final by = await db.spendByCategory(DateTime(2026, 7));
    expect(by[2], 1000);
    expect(by[null], 500);
    expect(by.values.fold(0, (a, b) => a + b), 1500, reason: 'credit excluded');
  });
}
