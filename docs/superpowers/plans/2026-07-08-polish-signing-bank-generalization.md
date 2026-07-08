# Polish, Signing & Bank Generalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix transaction ordering and add delete; rank notification categories by usage; move release builds off the debug signing key; replace the bank-sender allowlist with content-based transaction detection so any bank works.

**Architecture:** Seven independent tasks across three tracks (UX fixes, release signing, SMS detection). No schema changes. No new dependencies.

**Tech Stack:** Flutter/Dart, Drift (SQLite), Riverpod, Gradle Kotlin DSL, GitHub Actions.

## Global Constraints

- Money is always integer paise — never introduce a `double` for an amount.
- No network calls, no analytics, anywhere in this codebase.
- Do not invent new per-bank regex `BankPattern` entries — only ICICI (verified) and
  Kotak/Indian Bank (drafted/unverified) exist today, and that stays unchanged in this plan.
- Every task ends green: `flutter test` passes before moving to the next task.
- Spec: `docs/superpowers/specs/2026-07-08-polish-signing-bank-generalization-design.md`.

---

## Task 1: Fix same-day transaction ordering

Bank SMS usually carry a date with no time-of-day, so `parseIndianDate` returns
midnight and same-day transactions share an identical `txDate`. Both query sites that
order by `txDate` alone need a `createdAt DESC` tiebreaker.

**Files:**
- Modify: `lib/state/providers.dart:24-35` (`monthTxnsProvider`)
- Modify: `lib/data/daos.dart:41-50` (`monthTransactions`)
- Test: `test/db_test.dart` (add a test)
- Test: `test/providers_test.dart` (new file)

**Interfaces:**
- Produces: no signature changes — `monthTransactions(DateTime month) -> Future<List<Transaction>>` and `monthTxnsProvider` (`StreamProvider<List<Transaction>>`) keep their existing shapes; only row order changes.

- [ ] **Step 1: Write the failing DAO-level test**

Add to `test/db_test.dart`, inside `void main() { ... }`, after the `'duplicate by amount+account within 90s'` test:

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/db_test.dart`
Expected: FAIL — `rows.map((r) => r.id).toList()` returns `[firstId, secondId]` (insertion order), not `[secondId, firstId]`.

- [ ] **Step 3: Fix the DAO query**

In `lib/data/daos.dart`, replace the `monthTransactions` method body:

```dart
  /// All transactions in [month]'s calendar month, newest first. Same-day
  /// rows (common: bank SMS often carry no time-of-day) break ties by
  /// createdAt so the most recently captured shows first.
  Future<List<Transaction>> monthTransactions(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return (select(transactions)
          ..where((t) =>
              t.txDate.isBiggerOrEqualValue(start) &
              t.txDate.isSmallerThanValue(end))
          ..orderBy([
            (t) => OrderingTerm.desc(t.txDate),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/db_test.dart`
Expected: PASS

- [ ] **Step 5: Write the failing provider-level test**

Create `test/providers_test.dart`:

```dart
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

    final txns = await container.read(monthTxnsProvider.future);
    expect(txns.map((t) => t.id).toList(), [secondId, firstId]);
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/providers_test.dart`
Expected: FAIL — same tie-order problem as Step 2.

- [ ] **Step 7: Fix the provider query**

In `lib/state/providers.dart`, replace the `monthTxnsProvider` definition:

```dart
final monthTxnsProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(dbProvider);
  final month = ref.watch(selectedMonthProvider);
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  return (db.select(db.transactions)
        ..where((t) =>
            t.txDate.isBiggerOrEqualValue(start) &
            t.txDate.isSmallerThanValue(end))
        ..orderBy([
          (t) => OrderingTerm.desc(t.txDate),
          (t) => OrderingTerm.desc(t.createdAt),
        ]))
      .watch();
});
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/providers_test.dart`
Expected: PASS

- [ ] **Step 9: Run the full suite and commit**

Run: `flutter test`
Expected: all PASS

```bash
git add lib/data/daos.dart lib/state/providers.dart test/db_test.dart test/providers_test.dart
git commit -m "fix: break same-day transaction ties by createdAt, newest first"
```

---

## Task 2: Shared delete-with-undo widget, wired into Home too

Activity's swipe-to-delete (`transactions_screen.dart:_DismissibleTxn`) is private to that
file. Extract it into a public shared widget and use it in Home's Recent list, which
currently has no delete affordance.

**Files:**
- Modify: `lib/ui/widgets/common.dart` (add `DismissibleTxnTile`)
- Modify: `lib/ui/transactions_screen.dart:99-133` (remove `_DismissibleTxn`, use the shared widget)
- Modify: `lib/ui/home_screen.dart:54` (use the shared widget)
- Test: `test/home_screen_test.dart` (new file)

**Interfaces:**
- Produces: `DismissibleTxnTile({required Transaction txn})` — a `ConsumerWidget` in `lib/ui/widgets/common.dart`, drop-in replacement for `TxnTile` wherever swipe-to-delete is wanted.
- Consumes: `dbProvider` (`lib/state/providers.dart`), `TxnTile` (already in the same file).

- [ ] **Step 1: Write the failing widget test**

Create `test/home_screen_test.dart`:

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/home_screen_test.dart`
Expected: FAIL — Home renders a plain `TxnTile` with no `Dismissible` ancestor, so the drag does nothing and `'RAMESH KUMAR'` is still found.

- [ ] **Step 3: Extract the shared widget**

In `lib/ui/widgets/common.dart`, add after the `TxnTile` class:

```dart
/// Swipe-left-to-delete wrapper around [TxnTile], with an Undo snackbar.
class DismissibleTxnTile extends ConsumerWidget {
  final Transaction txn;

  const DismissibleTxnTile({super.key, required this.txn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    return Dismissible(
      key: ValueKey(txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete),
      ),
      onDismissed: (_) async {
        await (db.delete(db.transactions)..where((t) => t.id.equals(txn.id)))
            .go();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Deleted ${txn.merchant}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () =>
                  db.into(db.transactions).insert(txn.toCompanion(false)),
            ),
          ));
        }
      },
      child: TxnTile(txn: txn),
    );
  }
}
```

- [ ] **Step 4: Use the shared widget in Home**

In `lib/ui/home_screen.dart`, change:

```dart
              children: [for (final t in txns.take(10)) TxnTile(txn: t)],
```

to:

```dart
              children: [
                for (final t in txns.take(10)) DismissibleTxnTile(txn: t)
              ],
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/home_screen_test.dart`
Expected: PASS

- [ ] **Step 6: Replace Activity's private copy with the shared widget**

In `lib/ui/transactions_screen.dart`, delete the entire `_DismissibleTxn` class
(lines 99-133) and change its one usage:

```dart
                      for (final t in byDay[day]!) _DismissibleTxn(txn: t),
```

to:

```dart
                      for (final t in byDay[day]!) DismissibleTxnTile(txn: t),
```

- [ ] **Step 7: Run the full suite and commit**

Run: `flutter test`
Expected: all PASS (this includes the pre-existing Activity swipe-to-delete coverage,
now exercised through the shared widget)

```bash
git add lib/ui/widgets/common.dart lib/ui/home_screen.dart lib/ui/transactions_screen.dart test/home_screen_test.dart
git commit -m "feat: swipe-to-delete on Home's Recent list via shared widget"
```

---

## Task 3: Delete action in the transaction edit sheet

`txn_sheet.dart` has no way to delete a transaction while editing it.

**Files:**
- Modify: `lib/ui/txn_sheet.dart:113-130` (header row + new `_delete` method)
- Test: `test/txn_sheet_test.dart` (new file)

**Interfaces:**
- Consumes: `showTxnSheet(BuildContext, WidgetRef, {Transaction? existing, ...})` (unchanged signature).
- No new public interfaces — `_delete` is private to `_TxnFormState`.

- [ ] **Step 1: Write the failing widget test**

Create `test/txn_sheet_test.dart`:

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/txn_sheet_test.dart`
Expected: FAIL — no widget with text `'Delete'` exists in the sheet.

- [ ] **Step 3: Add the Delete button and confirmation flow**

In `lib/ui/txn_sheet.dart`, replace this line inside `_TxnFormState.build`:

```dart
            Text(widget.existing == null ? 'Add transaction' : 'Edit transaction',
                style: Theme.of(context).textTheme.titleLarge),
```

with:

```dart
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    widget.existing == null
                        ? 'Add transaction'
                        : 'Edit transaction',
                    style: Theme.of(context).textTheme.titleLarge),
                if (widget.existing != null)
                  TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error),
                    child: const Text('Delete'),
                  ),
              ],
            ),
```

Then add this method to `_TxnFormState`, right after `_save`:

```dart
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(dbProvider);
    await (db.delete(db.transactions)
          ..where((t) => t.id.equals(widget.existing!.id)))
        .go();
    if (mounted) Navigator.pop(context, true);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/txn_sheet_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full suite and commit**

Run: `flutter test`
Expected: all PASS

```bash
git add lib/ui/txn_sheet.dart test/txn_sheet_test.dart
git commit -m "feat: delete transaction from the edit sheet"
```

---

## Task 4: Rank notification quick-categories by usage

Notification quick-categorize actions currently show `db.allCategories()` — always the
first three seed categories in insertion order, never actual usage.

**Files:**
- Modify: `lib/data/daos.dart` (add `mostUsedCategories`)
- Modify: `lib/services/capture_service.dart:76` (use it)
- Test: `test/db_test.dart` (add a test)
- Test: `test/capture_service_test.dart` (add a test)

**Interfaces:**
- Produces: `Future<List<Category>> mostUsedCategories({int limit = 3})` on `AppDb` (via the `TransactionDao` extension in `lib/data/daos.dart`) — ranked by transaction count descending, padded with any remaining categories (in `allCategories()` order) up to `limit` so new users with no usage history still see options.
- Consumes: `allCategories()` (already exists, same file).

- [ ] **Step 1: Write the failing DAO-level test**

Add to `test/db_test.dart`, after the `'spendByCategory sums debits only'` test:

```dart
  test('mostUsedCategories ranks by usage, pads with unused categories',
      () async {
    // Seed order: Food=1, Groceries=2, Travel=3, Shopping=4, Bills=5, ...
    final t1 = await db.insertTransaction(txn(merchant: 'A'));
    await db.setCategory(t1, 2);
    final t2 = await db.insertTransaction(txn(merchant: 'B'));
    await db.setCategory(t2, 2);
    final t3 = await db.insertTransaction(txn(merchant: 'C'));
    await db.setCategory(t3, 5);

    final top = await db.mostUsedCategories(limit: 3);
    expect(top.map((c) => c.id).toList(), [2, 5, 1],
        reason: 'cat 2 used twice, cat 5 once, then pad with Food (id 1) '
            'since it is first in seed order and unused');
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/db_test.dart`
Expected: FAIL — `mostUsedCategories` doesn't exist yet (compile error).

- [ ] **Step 3: Implement the DAO method**

In `lib/data/daos.dart`, add to the `TransactionDao` extension, after `allCategories`:

```dart
  /// Categories ordered by all-time transaction count, most-used first.
  /// Categories with no transactions yet are appended (in [allCategories]
  /// order) so a fresh install still has options to offer.
  Future<List<Category>> mostUsedCategories({int limit = 3}) async {
    final txns = await select(transactions).get();
    final counts = <int, int>{};
    for (final t in txns) {
      final catId = t.categoryId;
      if (catId != null) counts[catId] = (counts[catId] ?? 0) + 1;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final all = await allCategories();
    final catMap = {for (final c in all) c.id: c};
    final result = <Category>[
      for (final e in ranked)
        if (catMap[e.key] != null) catMap[e.key]!
    ];
    for (final c in all) {
      if (result.length >= limit) break;
      if (!result.contains(c)) result.add(c);
    }
    return result.take(limit).toList();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/db_test.dart`
Expected: PASS

- [ ] **Step 5: Write the failing capture_service-level test**

Add to `test/capture_service_test.dart`, after the `'known merchant auto-categorized, no category actions'` test:

```dart
  test('notification offers most-used category first for a new merchant',
      () async {
    final t1 = await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 100,
      direction: TxnDirection.debit,
      merchant: 'X',
      txDate: at,
      source: TxnSource.manual,
    ));
    await db.setCategory(t1, 4);
    final t2 = await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: 200,
      direction: TxnDirection.debit,
      merchant: 'Y',
      txDate: at,
      source: TxnSource.manual,
    ));
    await db.setCategory(t2, 4);

    await svc.handleSms('AX-ICICIB-S', icici, at);
    final (_, _, cats) = notifier.txnCalls.single;
    expect(cats.first.id, 4,
        reason: 'category 4 used twice already, should rank first');
  });
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/capture_service_test.dart`
Expected: FAIL — `capture_service.dart` still calls `db.allCategories()`, so `cats.first.id` is `1` (Food), not `4`.

- [ ] **Step 7: Wire it into capture_service.dart**

In `lib/services/capture_service.dart`, change:

```dart
      final cats = knownCat == null ? await db.allCategories() : <Category>[];
```

to:

```dart
      final cats =
          knownCat == null ? await db.mostUsedCategories() : <Category>[];
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/capture_service_test.dart`
Expected: PASS

- [ ] **Step 9: Run the full suite and commit**

Run: `flutter test`
Expected: all PASS

```bash
git add lib/data/daos.dart lib/services/capture_service.dart test/db_test.dart test/capture_service_test.dart
git commit -m "feat: rank notification quick-categories by usage instead of insertion order"
```

---

## Task 5: Bank-agnostic SMS transaction detection

`isBankSender()` is a hard allowlist (ICICI/Kotak/Indian Bank DLT tokens only) used as
the entry gate in `capture_service.dart:handleSms`. Any SMS from an unrecognized sender
is dropped before parsing or the review queue ever see it — meaning a friend on
SBI/HDFC/Axis/etc. gets nothing captured. Replace the gate with a content-based
classifier that names no bank.

**Files:**
- Modify: `lib/parser/patterns.dart` (add `looksLikeTransactionSms`)
- Modify: `lib/parser/sms_parser.dart:4` (export it)
- Modify: `lib/services/capture_service.dart` (use it as the gate; remove `_looksTransactional`)
- Test: `test/parser_test.dart` (add a group)
- Test: `test/capture_service_test.dart` (replace one test with two)

**Interfaces:**
- Produces: `bool looksLikeTransactionSms(String sender, String body)` in `lib/parser/patterns.dart`, re-exported from `lib/parser/sms_parser.dart` alongside the existing `isBankSender`.
- `isBankSender()` and `SmsParser.parse()`'s internal sender check are unchanged — a
  message must still match a known `BankPattern` from a recognized bank sender to
  auto-store. `looksLikeTransactionSms` only controls whether an unmatched message is
  queued for review instead of silently dropped.

- [ ] **Step 1: Write the failing parser-level tests**

Add to `test/parser_test.dart`, after the `'helpers'` group, before the final closing
`}` of `main()`:

```dart
  group('looksLikeTransactionSms (bank-agnostic detection)', () {
    test('unrecognized business sender with transaction wording passes', () {
      expect(
          looksLikeTransactionSms(
              'VM-SOMEBANK', 'Rs 500 debited from A/c XX1234 via UPI'),
          isTrue);
    });
    test('known bank sender with a real sample still passes', () {
      expect(looksLikeTransactionSms('AX-ICICIB-S', icici), isTrue);
    });
    test('personal phone number sender rejected even with transaction wording',
        () {
      expect(
          looksLikeTransactionSms(
              '+919812345678', 'Rs 500 debited from A/c XX1234 via UPI'),
          isFalse);
    });
    test('otp rejected', () {
      expect(
          looksLikeTransactionSms(
              'AX-ICICIB-S', '482913 is the OTP for txn of Rs 55.00.'),
          isFalse);
    });
    test('promo without a direction verb rejected', () {
      expect(
          looksLikeTransactionSms('AX-ICICIB-S',
              'Get 10% cashback up to Rs 200 on your next UPI payment!'),
          isFalse);
    });
    test('balance enquiry rejected', () {
      expect(
          looksLikeTransactionSms(
              'AX-ICICIB-S', 'Avl Bal in Acct XX123 is Rs 12,345.67.'),
          isFalse);
    });
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/parser_test.dart`
Expected: FAIL — `looksLikeTransactionSms` doesn't exist yet (compile error).

- [ ] **Step 3: Implement the classifier**

In `lib/parser/patterns.dart`, add at the end of the file:

```dart
final _personalNumber = RegExp(r'^\+?(?:91)?\d{10}$');

/// True for a plain Indian mobile number. Bank/DLT alerts always come from
/// short alphanumeric business codes, never a personal number — this is the
/// only sender signal the generalized detector below relies on, and it
/// names no bank, so it works for any bank without a maintained allowlist.
bool _isPersonalNumber(String sender) =>
    _personalNumber.hasMatch(sender.trim());

final _amountPattern =
    RegExp(r'(?:rs\.?|inr|₹)\s?[\d,]+(?:\.\d{1,2})?', caseSensitive: false);
final _directionVerbs = RegExp(
    r'\b(debited|credited|debit|credit|withdrawn|spent|paid|received|sent)\b',
    caseSensitive: false);
final _bankContext = RegExp(
    r'\b(a/c|acct|account|card|upi|imps|neft|rtgs|ref no|txn)\b',
    caseSensitive: false);

/// True if [body] reads like a bank transaction alert, regardless of which
/// bank sent it or whether [sender] is a recognized bank sender ID. This is
/// the entry gate for capture: auto-store still requires a full match
/// against a known [BankPattern] (see [isBankSender], used inside
/// `SmsParser.parse`) — this function only decides whether an unmatched
/// message reaches the review queue instead of being dropped.
bool looksLikeTransactionSms(String sender, String body) {
  if (_isPersonalNumber(sender)) return false;
  final b = body.toLowerCase();
  if (b.contains('otp')) return false;
  if (b.contains('avl bal') || b.contains('available balance')) return false;
  return _amountPattern.hasMatch(b) &&
      _directionVerbs.hasMatch(b) &&
      _bankContext.hasMatch(b);
}
```

- [ ] **Step 4: Export it from sms_parser.dart**

In `lib/parser/sms_parser.dart`, change:

```dart
export 'patterns.dart' show isBankSender;
```

to:

```dart
export 'patterns.dart' show isBankSender, looksLikeTransactionSms;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/parser_test.dart`
Expected: PASS

- [ ] **Step 6: Write the failing capture_service-level tests**

In `test/capture_service_test.dart`, replace this entire test:

```dart
  test('non-bank sender ignored', () async {
    expect(await svc.handleSms('VM-AMAZON', icici, at), CaptureResult.ignored);
    expect(notifier.txnCalls, isEmpty);
  });
```

with:

```dart
  test(
      'unrecognized business sender with bank-formatted body is queued for '
      'review, not dropped', () async {
    expect(await svc.handleSms('VM-AMAZON', icici, at),
        CaptureResult.queuedForReview);
    expect(notifier.reviewCalls, [1]);
    expect(notifier.txnCalls, isEmpty);
  });

  test('personal phone number sender ignored even with bank-formatted body',
      () async {
    expect(await svc.handleSms('+919812345678', icici, at),
        CaptureResult.ignored);
    expect(notifier.txnCalls, isEmpty);
    expect(notifier.reviewCalls, isEmpty);
  });
```

- [ ] **Step 7: Run it to verify it fails**

Run: `flutter test test/capture_service_test.dart`
Expected: FAIL — `handleSms` still gates on `isBankSender(sender)` alone, so
`'VM-AMAZON'` is `ignored`, not `queuedForReview`.

- [ ] **Step 8: Replace the gate in capture_service.dart**

In `lib/services/capture_service.dart`, change:

```dart
    if (!isBankSender(sender)) return CaptureResult.ignored;

    final parsed = SmsParser.parse(sender, body, received: received);
    if (parsed == null) {
      // Bank sender but unparseable: never drop silently. OTP/promo noise is
      // filtered by _looksTransactional to keep the queue useful.
      if (!_looksTransactional(body)) return CaptureResult.ignored;
      await db.into(db.reviewQueue).insert(ReviewQueueCompanion.insert(
          sender: sender, body: body, receivedAt: received));
```

to:

```dart
    if (!looksLikeTransactionSms(sender, body)) return CaptureResult.ignored;

    final parsed = SmsParser.parse(sender, body, received: received);
    if (parsed == null) {
      // Passed the content-based gate above but matched no known BankPattern
      // (unrecognized bank, or a recognized bank sender in a format we
      // haven't seen): never drop silently, queue for manual review.
      await db.into(db.reviewQueue).insert(ReviewQueueCompanion.insert(
          sender: sender, body: body, receivedAt: received));
```

Then delete the now-unused `_looksTransactional` static method entirely (it was
folded into `looksLikeTransactionSms`):

```dart
  /// Debit/credit language without a parsed pattern → worth human review.
  static bool _looksTransactional(String body) {
    final b = body.toLowerCase();
    if (b.contains('otp')) return false;
    if (b.contains('avl bal') || b.contains('available balance')) return false;
    return (b.contains('debit') || b.contains('credit') || b.contains('sent')) &&
        RegExp(r'(?:rs\.?|inr|₹)\s?[\d,]+', caseSensitive: false).hasMatch(b);
  }
```

- [ ] **Step 9: Run test to verify it passes**

Run: `flutter test test/capture_service_test.dart`
Expected: PASS

- [ ] **Step 10: Run the full suite and commit**

Run: `flutter test`
Expected: all PASS — including the pre-existing `parser_test.dart` test
`'non-bank sender with txn-looking text'` (in the `'negatives — must not parse'`
group), which is unaffected: `SmsParser.parse` still requires `isBankSender` for a
full match, so it still returns `null` for `'VM-AMAZON'` regardless of body content.

```bash
git add lib/parser/patterns.dart lib/parser/sms_parser.dart lib/services/capture_service.dart test/parser_test.dart test/capture_service_test.dart
git commit -m "feat: bank-agnostic SMS detection — content signals replace sender allowlist"
```

---

## Task 6: Release keystore and Gradle signing config

Release builds currently sign with the debug key
(`android/app/build.gradle.kts:33`), which is why a new build can conflict with an
already-installed one and force a data-losing reinstall. Generate a real keystore and
wire it in, falling back to the debug key only when no keystore is configured (so a
fresh checkout without the keystore — e.g. a friend building from source — still
builds).

**Files:**
- Create: `android/app/upload-keystore.jks` (binary, gitignored)
- Create: `android/key.properties` (gitignored)
- Modify: `android/app/build.gradle.kts`
- Modify: `.gitignore`

**Interfaces:** None (build configuration only, no Dart code).

- [ ] **Step 1: Generate the keystore**

```bash
cd android/app
STOREPASS=$(openssl rand -base64 24)
KEYPASS=$(openssl rand -base64 24)
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload \
  -storepass "$STOREPASS" -keypass "$KEYPASS" \
  -dname "CN=FinTrack, OU=Personal, O=Suprasidh, L=Unknown, S=Unknown, C=IN"
cd ../..
```

Expected: `Generating 2,048 bit RSA key pair and self-signed certificate ...` then
`[Storing upload-keystore.jks]`.

- [ ] **Step 2: Write key.properties**

```bash
cat > android/key.properties <<EOF
storePassword=$STOREPASS
keyPassword=$KEYPASS
keyAlias=upload
storeFile=upload-keystore.jks
EOF
echo "STORE PASSWORD: $STOREPASS"
echo "KEY PASSWORD:   $KEYPASS"
```

**Copy the two printed passwords, plus `android/app/upload-keystore.jks` itself, into
a password manager or other durable backup now.** Neither is recoverable if lost, and
losing them means no future release can ever cleanly update an existing install.

- [ ] **Step 3: Gitignore the generated secrets**

Add to `.gitignore`, after the `# Android Studio will place build artifacts here`
section:

```
# Release signing (generated locally in Task 6 — never commit)
/android/key.properties
/android/app/*.jks
/android/app/*.keystore
```

- [ ] **Step 4: Wire signing into build.gradle.kts**

Replace the full contents of `android/app/build.gradle.kts` with:

```kotlin
import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.suprasidh.fintrack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "dev.suprasidh.fintrack"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key only when key.properties is absent
            // (e.g. a fresh checkout before running Task 6's keystore setup).
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

- [ ] **Step 5: Build and verify the signature**

```bash
flutter build apk --release
keytool -printcert -jarfile build/app/outputs/flutter-apk/app-release.apk | grep Owner
```

Expected: `Owner: CN=FinTrack, OU=Personal, O=Suprasidh, L=Unknown, S=Unknown, C=IN`
— NOT `CN=Android Debug,O=Android,C=US` (the debug cert's fixed subject).

- [ ] **Step 6: Run the full suite and commit**

Run: `flutter test`
Expected: all PASS (this task touches no Dart code, so nothing here should change)

```bash
git add android/app/build.gradle.kts .gitignore
git commit -m "build: sign release APKs with a real keystore instead of the debug key"
```

Note: `android/key.properties` and `android/app/upload-keystore.jks` are intentionally
not staged — they're gitignored and must never enter the repo.

---

## Task 7: Sign CI-built releases with the same keystore

The GitHub Actions release workflow (`.github/workflows/android-release.yml`) builds
with `flutter build apk --release`, which now (after Task 6) needs `android/key.properties`
and the keystore file present to sign with the release key instead of falling back to
debug. Wire this via repo secrets so CI-built and locally-built releases carry the same
signature.

**Files:**
- Modify: `.github/workflows/android-release.yml`

**Interfaces:** None (CI configuration only).

- [ ] **Step 1: Add the signing steps to the workflow**

In `.github/workflows/android-release.yml`, insert two new steps between
`Install dependencies` and `Build release APK`:

```yaml
      - name: Decode release keystore
        run: echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 -d > android/app/upload-keystore.jks

      - name: Write key.properties
        run: |
          cat > android/key.properties <<EOF
          storePassword=${{ secrets.ANDROID_STORE_PASSWORD }}
          keyPassword=${{ secrets.ANDROID_KEY_PASSWORD }}
          keyAlias=upload
          storeFile=upload-keystore.jks
          EOF
```

The full `steps:` list should now read: Checkout, Setup JDK 17, Setup Flutter, Install
dependencies, **Decode release keystore**, **Write key.properties**, Build release APK,
Rename release artifact, Create GitHub release.

- [ ] **Step 2: Push the keystore and passwords as repo secrets**

**This step uploads secrets to GitHub — confirm with the user before running it.**
Uses the passwords generated in Task 6, Step 2 (`$STOREPASS`, `$KEYPASS`) — if that
shell session is gone, re-read them from `android/key.properties`.

```bash
base64 < android/app/upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64 --repo suprxsidh/fintrack
gh secret set ANDROID_STORE_PASSWORD --repo suprxsidh/fintrack --body "$STOREPASS"
gh secret set ANDROID_KEY_PASSWORD --repo suprxsidh/fintrack --body "$KEYPASS"
```

Expected: `gh` prints `✓ Set secret ANDROID_KEYSTORE_BASE64 for suprxsidh/fintrack` (and
similarly for the other two) after each command.

- [ ] **Step 3: Verify with a real tagged release**

```bash
git tag v0.0.0-signing-test
git push origin v0.0.0-signing-test
gh run watch --repo suprxsidh/fintrack
```

Expected: the workflow run succeeds. Download the resulting release APK and confirm
its signature matches Task 6's:

```bash
gh release download v0.0.0-signing-test --repo suprxsidh/fintrack -p '*.apk' -D /tmp/fintrack-ci-check
keytool -printcert -jarfile /tmp/fintrack-ci-check/*.apk | grep Owner
```

Expected: same `Owner: CN=FinTrack, ...` line as Task 6, Step 5.

Clean up the test tag and release afterward:

```bash
gh release delete v0.0.0-signing-test --repo suprxsidh/fintrack --yes
git push origin :refs/tags/v0.0.0-signing-test
git tag -d v0.0.0-signing-test
rm -rf /tmp/fintrack-ci-check
```

- [ ] **Step 4: Commit the workflow change**

```bash
git add .github/workflows/android-release.yml
git commit -m "ci: sign release builds with the release keystore via repo secrets"
```

---

## After this plan

Not a coding task, but part of getting to the next real install: the next time you
uninstall the current debug-signed build to install one signed with the new release
key, export CSV from Settings first (existing feature, `lib/services/csv_service.dart`)
and re-import after. Budgets and recurring rules aren't covered by CSV — worth a quick
manual re-entry, or say the word and a full DB backup/restore file (already on
`future_plans.md`) can be pulled forward into its own plan.
