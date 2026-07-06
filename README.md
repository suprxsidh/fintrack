# FinTrack

Local-first personal finance tracker for Android. Reads Indian bank SMS (ICICI, Kotak, Indian Bank) and turns them into transactions automatically. No cloud, no analytics, no network calls: everything stays on your phone.

## Download

**[⬇ Download the APK](https://github.com/suprxsidh/fintrack/releases/latest/download/app-release.apk)** (Android 8.0+, arm64)

Install it by opening the downloaded file. You may need to allow "install from unknown sources" since this is a sideloaded app, not a Play Store one.

On first launch, grant SMS and notification permissions so the app can read incoming bank messages.

## What it does

- **Auto-capture**: incoming bank SMS become transactions. Tap the notification to categorize on the spot.
- **History import**: scan your existing SMS inbox and import past transactions in bulk.
- **Budgets**: monthly budgets per category with progress tracking.
- **Insights**: spending charts by category and over time.
- **Subscriptions**: recurring payments detected automatically and tracked.
- **Review queue**: low-confidence parses land in a queue instead of polluting your data.
- **Export**: CSV export/import and a monthly PDF report.

## Privacy

All data lives in a local SQLite database on the device. The app has no analytics SDK and never uploads anything.

## Supported banks

| Bank | Status |
|------|--------|
| ICICI (UPI debit) | Verified against real SMS |
| ICICI (credit, card spend) | Drafted, needs real samples |
| Kotak | Drafted, needs real samples |
| Indian Bank | Drafted, needs real samples |

Unrecognized bank SMS are ignored. To add a bank, add a regex pattern in `lib/parser/patterns.dart`.

## Building from source

```bash
flutter pub get
flutter build apk --release
```

Requires Flutter (Dart 3), Android SDK 34+, JDK 21.

## Stack

Flutter, Riverpod, Drift (SQLite), fl_chart, flutter_local_notifications, another_telephony.
