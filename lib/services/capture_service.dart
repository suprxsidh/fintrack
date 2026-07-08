import 'package:drift/drift.dart';

import '../data/daos.dart';
import '../data/db.dart';
import '../parser/sms_parser.dart';

enum CaptureResult { stored, duplicate, queuedForReview, ignored }

/// Notification side-effects, mockable in tests. Real impl lives in
/// notif_service.dart (plugin-backed, exercised in the emulator E2E).
abstract class TxnNotifier {
  /// [categories] are offered as quick actions when the txn is uncategorized.
  Future<void> showTxn(int txnId, Transaction txn, List<Category> categories);

  Future<void> showReviewNeeded(int queueCount);
}

class CaptureService {
  final AppDb db;
  final TxnNotifier notifier;

  CaptureService(this.db, this.notifier);

  /// Full pipeline for one SMS: filter → parse → dedup → auto-categorize →
  /// store → notify. [notify] false during bulk history import.
  Future<CaptureResult> handleSms(
    String sender,
    String body,
    DateTime received, {
    bool notify = true,
    TxnSource source = TxnSource.sms,
  }) async {
    if (!looksLikeTransactionSms(sender, body)) return CaptureResult.ignored;

    final parsed = SmsParser.parse(sender, body, received: received);
    if (parsed == null) {
      // Passed the content-based gate above but matched no known BankPattern
      // (unrecognized bank, or a recognized bank sender in a format we
      // haven't seen): never drop silently, queue for manual review.
      await db.into(db.reviewQueue).insert(ReviewQueueCompanion.insert(
          sender: sender, body: body, receivedAt: received));
      if (notify) {
        final pending = await (db.select(db.reviewQueue)
              ..where((r) => r.resolved.equals(false)))
            .get();
        await notifier.showReviewNeeded(pending.length);
      }
      return CaptureResult.queuedForReview;
    }

    final dup = await db.isDuplicate(
      amountPaise: parsed.amountPaise,
      accountTail: parsed.accountTail,
      smsRef: parsed.ref,
      txDate: parsed.txDate,
    );
    if (dup) return CaptureResult.duplicate;

    final knownCat = await db.categoryFor(parsed.merchant);
    final id = await db.insertTransaction(TransactionsCompanion.insert(
      amountPaise: parsed.amountPaise,
      direction: parsed.direction,
      merchant: parsed.merchant,
      categoryId: Value(knownCat),
      accountTail: Value(parsed.accountTail),
      txDate: parsed.txDate,
      source: source,
      rawSms: Value(body),
      smsRef: Value(parsed.ref),
    ));

    if (notify) {
      final txn = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      final cats =
          knownCat == null ? await db.mostUsedCategories() : <Category>[];
      await notifier.showTxn(id, txn, cats);
    }
    return CaptureResult.stored;
  }
}
