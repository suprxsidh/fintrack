import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import '../data/daos.dart';
import '../data/db.dart';
import 'capture_service.dart';
import 'db_holder.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

String formatPaise(int paise) => _inr.format(paise / 100);

/// Android caps notification actions at 3: we offer the 3 most common
/// categories; tapping the notification body opens the app on the txn.
class LocalTxnNotifier implements TxnNotifier {
  final FlutterLocalNotificationsPlugin plugin;

  LocalTxnNotifier(this.plugin);

  static const channel = AndroidNotificationDetails(
    'txn_capture',
    'Transaction capture',
    channelDescription: 'New expenses detected from bank SMS',
    importance: Importance.high,
    priority: Priority.high,
  );

  @override
  Future<void> showTxn(
      int txnId, Transaction txn, List<Category> categories) async {
    final verb = txn.direction == TxnDirection.debit ? 'spent' : 'received';
    final actions = categories
        .take(3)
        .map((c) => AndroidNotificationAction('cat_${c.id}', '${c.emoji} ${c.name}',
            showsUserInterface: false, cancelNotification: true))
        .toList();
    await plugin.show(
      id: txnId,
      title: '${formatPaise(txn.amountPaise)} $verb',
      body: '${txn.merchant}${categories.isEmpty ? '' : ' · tap a category'}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.channelId,
          channel.channelName,
          channelDescription: channel.channelDescription,
          importance: channel.importance,
          priority: channel.priority,
          actions: actions,
        ),
      ),
      payload: 'txn:$txnId',
    );
  }

  @override
  Future<void> showReviewNeeded(int queueCount) => plugin.show(
        id: -1, // fixed id: review notifications coalesce
        title: 'FinTrack',
        body: '$queueCount SMS need review',
        notificationDetails: const NotificationDetails(android: channel),
        payload: 'review',
      );
}

/// Handles notification action taps. Runs in a background isolate when the
/// app is dead, so it must open its own DB handle via [openAppDb].
@pragma('vm:entry-point')
Future<void> onNotificationResponse(NotificationResponse response) async {
  final actionId = response.actionId;
  final payload = response.payload;
  if (actionId == null || payload == null) return;
  if (!actionId.startsWith('cat_') || !payload.startsWith('txn:')) return;
  final catId = int.tryParse(actionId.substring(4));
  final txnId = int.tryParse(payload.substring(4));
  if (catId == null || txnId == null) return;
  final db = openAppDb();
  try {
    await db.setCategory(txnId, catId);
  } finally {
    await db.close();
  }
}
