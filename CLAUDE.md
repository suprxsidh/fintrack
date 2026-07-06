# FinTrack

Android-only, local-first finance tracker. Auto-reads bank SMS (ICICI, Kotak, Indian Bank),
actionable notification categorization, budgets, insights, recurring, CSV/PDF export.
Spec: `docs/superpowers/specs/2026-07-06-fintrack-design.md`.

## Constraints

- Personal app, sideloaded APK — no Play Store rules apply, READ_SMS/RECEIVE_SMS is fine.
- ALL data local. No network calls, no analytics, no cloud.
- Money = integer paise. Never float.
- Cashew is design INSPIRATION only — its source is unlicensed; never copy code from it.
- Kotak / Indian Bank regex patterns are UNVERIFIED (drafted from known formats). Only the
  ICICI debit pattern is from a real sample. Get real SMS from user before trusting them.

## Toolchain (this Mac)

- ANDROID_HOME=/opt/homebrew/share/android-commandlinetools (platforms 34/35, build-tools 34.0.0)
- Flutter + temurin@21 via brew cask
- adb at /opt/homebrew/bin/adb

## Working notes

- User checks in intermittently; build autonomously, keep BUILD_LOG.md updated.
