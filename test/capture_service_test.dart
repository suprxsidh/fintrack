import 'package:drift/native.dart';
import 'package:fintrack/data/daos.dart';
import 'package:fintrack/data/db.dart';
import 'package:fintrack/services/capture_service.dart';
import 'package:flutter_test/flutter_test.dart';

const icici = 'ICICI Bank Acct XX123 debited for Rs 55.00 on 06-Jul-26; '
    'RAMESH KUMAR credited. UPI:412345678901. Call 18002662 for dispute.';

class FakeNotifier implements TxnNotifier {
  final txnCalls = <(int, Transaction, List<Category>)>[];
  final reviewCalls = <int>[];

  @override
  Future<void> showTxn(
          int txnId, Transaction txn, List<Category> categories) async =>
      txnCalls.add((txnId, txn, categories));

  @override
  Future<void> showReviewNeeded(int queueCount) async =>
      reviewCalls.add(queueCount);
}

void main() {
  late AppDb db;
  late FakeNotifier notifier;
  late CaptureService svc;
  final at = DateTime(2026, 7, 6, 12);

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    notifier = FakeNotifier();
    svc = CaptureService(db, notifier);
  });
  tearDown(() => db.close());

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

  test('parseable sms stored + notified with category choices', () async {
    expect(
        await svc.handleSms('AX-ICICIB-S', icici, at), CaptureResult.stored);
    final (id, txn, cats) = notifier.txnCalls.single;
    expect(txn.amountPaise, 5500);
    expect(txn.categoryId, isNull);
    expect(cats, isNotEmpty, reason: 'uncategorized → offer categories');
    expect((await db.monthTransactions(DateTime(2026, 7))).length, 1);
    expect(id, txn.id);
  });

  test('known merchant auto-categorized, no category actions', () async {
    await svc.handleSms('AX-ICICIB-S', icici, at);
    await db.setCategory(notifier.txnCalls.single.$1, 3);
    // same merchant, later different txn
    final body2 = icici
        .replaceFirst('55.00', '80.00')
        .replaceFirst('412345678901', '777');
    await svc.handleSms(
        'AX-ICICIB-S', body2, at.add(const Duration(hours: 2)));
    final (_, txn2, cats2) = notifier.txnCalls.last;
    expect(txn2.categoryId, 3, reason: 'merchant memory applied');
    expect(cats2, isEmpty, reason: 'already categorized');
  });

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

  test('duplicate sms not stored twice', () async {
    await svc.handleSms('AX-ICICIB-S', icici, at);
    expect(await svc.handleSms('AX-ICICIB-S', icici, at),
        CaptureResult.duplicate);
    expect((await db.monthTransactions(DateTime(2026, 7))).length, 1);
  });

  test('unparseable transactional sms queued for review', () async {
    const weird = 'Rs 99 debited via NEFT from your account. New format!';
    expect(await svc.handleSms('AX-ICICIB-S', weird, at),
        CaptureResult.queuedForReview);
    expect(notifier.reviewCalls, [1]);
  });

  test('bank promo/otp ignored, not queued', () async {
    expect(
        await svc.handleSms('AX-ICICIB-S',
            '482913 is the OTP for txn of Rs 55.00. Do not share.', at),
        CaptureResult.ignored);
    expect(
        await svc.handleSms('AX-ICICIB-S',
            'Get 10% cashback up to Rs 200 on UPI!', at),
        CaptureResult.ignored);
    expect(notifier.reviewCalls, isEmpty);
  });

  test('bank match with trailing balance line still stored, not dropped',
      () async {
    final withBalance = '$icici Avl Bal: Rs 5,000.00.';
    expect(await svc.handleSms('AX-ICICIB-S', withBalance, at),
        CaptureResult.stored);
  });

  test('import mode: stored silently', () async {
    expect(
        await svc.handleSms('AX-ICICIB-S', icici, at,
            notify: false, source: TxnSource.imported),
        CaptureResult.stored);
    expect(notifier.txnCalls, isEmpty);
    final rows = await db.monthTransactions(DateTime(2026, 7));
    expect(rows.single.source, TxnSource.imported);
  });
}
