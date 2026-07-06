import 'package:csv/csv.dart';
import 'package:drift/drift.dart';

import '../data/daos.dart';
import '../data/db.dart';

/// CSV is both export format and restore path (data is local-only, so this
/// doubles as backup). Columns are stable — treat as a public contract.
const csvHeader = [
  'date', 'amount', 'direction', 'merchant', 'category', 'account', 'note', 'source',
];

class CsvService {
  final AppDb db;

  CsvService(this.db);

  Future<String> export() async {
    final txns = await (db.select(db.transactions)
          ..orderBy([(t) => OrderingTerm.asc(t.txDate)]))
        .get();
    final cats = {for (final c in await db.allCategories()) c.id: c.name};
    final rows = [
      csvHeader,
      for (final t in txns)
        [
          t.txDate.toIso8601String().substring(0, 10),
          (t.amountPaise / 100).toStringAsFixed(2),
          t.direction.name,
          t.merchant,
          t.categoryId == null ? '' : cats[t.categoryId] ?? '',
          t.accountTail ?? '',
          t.note ?? '',
          t.source.name,
        ],
    ];
    return Csv(lineDelimiter: '\n').encode(rows);
  }

  /// Imports rows, skipping duplicates (same date+amount+merchant already
  /// present). Unknown category names are created on the fly.
  Future<(int added, int skipped)> import(String csvText) async {
    final rows = Csv().decode(csvText);
    if (rows.isEmpty) return (0, 0);
    var start = 0;
    if (rows.first.map((c) => c.toString()).join(',') == csvHeader.join(',')) {
      start = 1;
    }
    final catIdByName = {
      for (final c in await db.allCategories()) c.name.toLowerCase(): c.id
    };
    var added = 0, skipped = 0;
    for (final row in rows.skip(start)) {
      if (row.length < csvHeader.length) continue;
      final date = DateTime.tryParse(row[0].toString());
      final amount = double.tryParse(row[1].toString());
      if (date == null || amount == null) continue;
      final paise = (amount * 100).round();
      final merchant = row[3].toString();

      final existing = await (db.select(db.transactions)
            ..where((t) =>
                t.amountPaise.equals(paise) &
                t.merchant.equals(merchant) &
                t.txDate.isBetweenValues(
                    date, date.add(const Duration(days: 1)))))
          .get();
      if (existing.isNotEmpty) {
        skipped++;
        continue;
      }

      final catName = row[4].toString().trim();
      int? catId;
      if (catName.isNotEmpty) {
        catId = catIdByName[catName.toLowerCase()];
        catId ??= await db.into(db.categories).insert(
            CategoriesCompanion.insert(
                name: catName, emoji: '🏷️', colorHex: '78909C'));
        catIdByName[catName.toLowerCase()] = catId;
      }

      await db.insertTransaction(TransactionsCompanion.insert(
        amountPaise: paise,
        direction: row[2].toString() == 'credit'
            ? TxnDirection.credit
            : TxnDirection.debit,
        merchant: merchant,
        categoryId: Value(catId),
        accountTail:
            Value(row[5].toString().isEmpty ? null : row[5].toString()),
        txDate: date,
        source: TxnSource.imported,
        note: Value(row[6].toString().isEmpty ? null : row[6].toString()),
      ));
      added++;
    }
    return (added, skipped);
  }
}
