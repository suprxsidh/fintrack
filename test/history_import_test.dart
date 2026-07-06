import 'package:drift/native.dart';
import 'package:fintrack/data/daos.dart';
import 'package:fintrack/data/db.dart';
import 'package:fintrack/services/capture_service.dart';
import 'package:fintrack/services/history_import.dart';
import 'package:flutter_test/flutter_test.dart';

class SilentNotifier implements TxnNotifier {
  int calls = 0;

  @override
  Future<void> showTxn(int txnId, Transaction txn, List<Category> c) async =>
      calls++;

  @override
  Future<void> showReviewNeeded(int queueCount) async => calls++;
}

void main() {
  test('import: parses, dedups, queues, skips junk, never notifies', () async {
    final db = AppDb(NativeDatabase.memory());
    final notifier = SilentNotifier();
    final importer = HistoryImporter(CaptureService(db, notifier));
    final now = DateTime.now();

    const icici = 'ICICI Bank Acct XX106 debited for Rs 55.00 on 06-Jul-26; '
        'PRAVEEN R V credited. UPI:655315924126.';
    final inbox = [
      InboxSms('AX-ICICIB-S', icici, now),
      InboxSms('AX-ICICIB-S', icici, now), // exact duplicate
      InboxSms('AX-ICICIB-S', 'Rs 99 debited via NEFT. New format!', now),
      InboxSms('VM-AMAZON', 'Your order shipped', now), // junk
      InboxSms('AX-ICICIB-S', icici,
          now.subtract(const Duration(days: 400))), // too old
    ];

    final s = await importer.import(inbox);
    expect(s.added, 1);
    expect(s.skipped, 1);
    expect(s.queued, 1);
    expect(notifier.calls, 0, reason: 'import is silent');

    final rows = await db.monthTransactions(DateTime(2026, 7));
    expect(rows.single.source, TxnSource.imported);
    await db.close();
  });
}
