import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/capture_service.dart';
import 'services/db_holder.dart';
import 'services/notif_service.dart';
import 'state/providers.dart';
import 'ui/app.dart';

final _notifPlugin = FlutterLocalNotificationsPlugin();

Future<void> _initNotifications() async {
  await _notifPlugin.initialize(
    settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    onDidReceiveNotificationResponse: onNotificationResponse,
    onDidReceiveBackgroundNotificationResponse: onNotificationResponse,
  );
}

/// Runs in a background isolate when an SMS arrives and the app is dead.
@pragma('vm:entry-point')
Future<void> backgroundSmsHandler(SmsMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();
  final db = openAppDb();
  try {
    await CaptureService(db, LocalTxnNotifier(plugin)).handleSms(
      message.address ?? '',
      message.body ?? '',
      DateTime.now(),
    );
  } finally {
    await db.close();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();

  final telephony = Telephony.instance;
  final granted = await telephony.requestPhoneAndSmsPermissions ?? false;
  await _notifPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  final db = openAppDb();
  if (granted) {
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        CaptureService(db, LocalTxnNotifier(_notifPlugin)).handleSms(
          message.address ?? '',
          message.body ?? '',
          DateTime.now(),
        );
      },
      onBackgroundMessage: backgroundSmsHandler,
    );
  }

  runApp(ProviderScope(
    overrides: [dbProvider.overrideWithValue(db)],
    child: const FinTrackApp(),
  ));
}
