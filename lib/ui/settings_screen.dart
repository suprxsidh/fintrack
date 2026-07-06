import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/capture_service.dart';
import '../services/history_import.dart';
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
      ],
    );
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
