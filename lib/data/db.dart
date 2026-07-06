import 'package:drift/drift.dart';

part 'db.g.dart';

enum TxnDirection { debit, credit }

enum TxnSource { sms, manual, imported }

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get amountPaise => integer()();
  IntColumn get direction => intEnum<TxnDirection>()();
  TextColumn get merchant => text()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  TextColumn get accountTail => text().nullable()();
  DateTimeColumn get txDate => dateTime()();
  IntColumn get source => intEnum<TxnSource>()();
  TextColumn get rawSms => text().nullable()();
  TextColumn get smsRef => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get emoji => text()();
  TextColumn get colorHex => text()();
  BoolColumn get isSeed => boolean().withDefault(const Constant(false))();
}

class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  // null categoryId = overall budget
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  IntColumn get amountPaise => integer()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class RecurringRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get amountPaise => integer().nullable()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  TextColumn get merchantMatch => text()();
  IntColumn get dueDay => integer()();
  DateTimeColumn get lastSeen => dateTime().nullable()();
}

class ReviewQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sender => text()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();
  BoolColumn get resolved => boolean().withDefault(const Constant(false))();
}

class MerchantMemory extends Table {
  TextColumn get merchant => text()();
  IntColumn get categoryId => integer().references(Categories, #id)();

  @override
  Set<Column> get primaryKey => {merchant};
}

@DriftDatabase(tables: [
  Transactions,
  Categories,
  Budgets,
  RecurringRules,
  ReviewQueue,
  MerchantMemory,
])
class AppDb extends _$AppDb {
  AppDb(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await batch((b) => b.insertAll(categories, _seedCategories));
        },
      );
}

final _seedCategories = [
  ('Food', '🍔', 'FF7043'),
  ('Groceries', '🛒', '66BB6A'),
  ('Travel', '🚕', '42A5F5'),
  ('Shopping', '🛍️', 'AB47BC'),
  ('Bills', '💡', 'FFA726'),
  ('Entertainment', '🎬', 'EC407A'),
  ('Health', '💊', '26A69A'),
  ('Rent', '🏠', '8D6E63'),
  ('Other', '📦', '78909C'),
]
    .map((c) => CategoriesCompanion.insert(
        name: c.$1, emoji: c.$2, colorHex: c.$3, isSeed: const Value(true)))
    .toList();
