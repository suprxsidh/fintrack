import 'package:drift_flutter/drift_flutter.dart';

import '../data/db.dart';

/// One canonical way to open the app database file. Every isolate (UI,
/// background SMS handler, notification action handler) goes through this so
/// they all hit the same file with drift's cross-isolate coordination.
AppDb openAppDb() => AppDb(driftDatabase(
      name: 'fintrack',
      native: const DriftNativeOptions(shareAcrossIsolates: true),
    ));
