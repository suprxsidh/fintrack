import 'dart:io';

import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/capture_service.dart';
import '../services/csv_service.dart';
import '../services/history_import.dart';
import '../services/pdf_report.dart';
import '../state/providers.dart';
import 'categories_screen.dart';
import 'review_screen.dart';

/// The "More" tab: review queue, categories, data tools.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(reviewQueueProvider).value?.length ?? 0;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: const Icon(Icons.rule),
          title: const Text('Needs review'),
          subtitle: Text(pending == 0
              ? 'No SMS waiting'
              : '$pending SMS could not be parsed'),
          trailing: pending == 0 ? null : Badge(label: Text('$pending')),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ReviewScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Categories'),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CategoriesScreen())),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Import SMS history'),
          subtitle: const Text('Scan the last 6 months of bank SMS'),
          onTap: () => _runImport(context, ref),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.table_view_outlined),
          title: const Text('Export CSV'),
          subtitle: const Text('All transactions · doubles as a backup'),
          onTap: () => _exportCsv(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('Monthly PDF report'),
          subtitle: const Text('Statement for the selected month'),
          onTap: () => _exportPdf(context, ref),
        ),
      ],
    );
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = await CsvService(ref.read(dbProvider)).export();
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/fintrack_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)], subject: 'FinTrack export'));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final month = ref.read(selectedMonthProvider);
      final bytes = await PdfReport(ref.read(dbProvider)).build(month);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/fintrack_${DateFormat('yyyy_MM').format(month)}.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)], subject: 'FinTrack monthly report'));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Report failed: $e')));
    }
  }

  Future<void> _runImport(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Scanning inbox…')));
    try {
      final messages = await Telephony.instance.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      );
      final inbox = messages.map((m) => InboxSms(
            m.address ?? '',
            m.body ?? '',
            DateTime.fromMillisecondsSinceEpoch(m.date ?? 0),
          ));
      final db = ref.read(dbProvider);
      final summary = await HistoryImporter(
              CaptureService(db, _NoopNotifier()))
          .import(inbox);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Import: $summary')));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}

class _NoopNotifier implements TxnNotifier {
  @override
  Future<void> showTxn(txnId, txn, categories) async {}

  @override
  Future<void> showReviewNeeded(int queueCount) async {}
}
