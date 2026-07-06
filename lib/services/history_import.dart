import '../data/db.dart';
import 'capture_service.dart';

class ImportSummary {
  int added = 0;
  int skipped = 0;
  int queued = 0;

  @override
  String toString() => '$added added, $skipped skipped, $queued for review';
}

/// One inbox SMS, decoupled from the telephony plugin so this is testable
/// and reusable. The settings screen adapts plugin messages into this.
class InboxSms {
  final String sender;
  final String body;
  final DateTime receivedAt;

  const InboxSms(this.sender, this.body, this.receivedAt);
}

class HistoryImporter {
  final CaptureService capture;

  HistoryImporter(this.capture);

  /// Runs every inbox SMS from the last [months] through the normal capture
  /// pipeline, silently (no notifications). Dedup makes this re-runnable.
  Future<ImportSummary> import(
    Iterable<InboxSms> inbox, {
    int months = 6,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: months * 30));
    final summary = ImportSummary();
    for (final sms in inbox) {
      if (sms.receivedAt.isBefore(cutoff)) continue;
      final result = await capture.handleSms(
        sms.sender,
        sms.body,
        sms.receivedAt,
        notify: false,
        source: TxnSource.imported,
      );
      switch (result) {
        case CaptureResult.stored:
          summary.added++;
        case CaptureResult.duplicate:
          summary.skipped++;
        case CaptureResult.queuedForReview:
          summary.queued++;
        case CaptureResult.ignored:
          break;
      }
    }
    return summary;
  }
}
