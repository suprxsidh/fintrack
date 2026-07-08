# FinTrack — Polish, Signing & Bank Generalization (2026-07-08)

## What

Three independent tracks, bundled into one release because Track 2 forces a reinstall
anyway:

1. **UX fixes**: transaction ordering, delete, smarter notification categories.
2. **Release signing + data migration**: fix debug-signed release builds; bridge
   yesterday's data across the resulting reinstall.
3. **Bank-agnostic SMS detection**: stop relying on a sender/bank allowlist so
   friends on any bank can test the app.

## Track 1 — UX fixes

### Transaction ordering (bug)

Root cause: `parseIndianDate` in `lib/parser/sms_parser.dart` returns a date with no
time-of-day (bank SMS rarely include one), so same-day transactions share an identical
`txDate`. `monthTxnsProvider` (`lib/state/providers.dart`) orders by `txDate` alone, so
same-day ties fall back to SQLite's arbitrary tie order — effectively oldest-inserted-first,
not most-recent-first.

Fix: order by `txDate DESC, createdAt DESC`. `createdAt` holds the real capture
timestamp, so this breaks ties correctly. One query change; Home (`home_screen.dart`,
`txns.take(10)`) and Activity (`transactions_screen.dart`, grouped-by-day) both read from
`monthTxnsProvider` and inherit the fix.

### Delete transactions

Activity tab already supports swipe-to-delete with an Undo snackbar
(`transactions_screen.dart:_DismissibleTxn`). Two gaps:

- Home tab's "Recent" list (`home_screen.dart`) has no delete affordance.
- The transaction edit sheet (`txn_sheet.dart`) has no delete action.

Fix: factor the dismiss+undo logic out of `_DismissibleTxn` into a shared widget in
`widgets/common.dart`, reuse it in Home's Recent list. Add a "Delete" action to
`txn_sheet.dart` with a confirmation dialog, closing the sheet on success.

### Notification categories

Custom categories already work end-to-end (Settings → Categories:
`categories_screen.dart`, add/edit/delete, no changes needed). The gap is what the
notification offers as quick-categorize actions: `capture_service.dart` currently passes
`db.allCategories()` (raw insertion order) to `notifier.showTxn`, so the three action
buttons are always the first three seed categories regardless of actual usage.

Fix: add a DAO method that counts transactions per category (all-time, all categories)
and returns the top N by count. `capture_service.dart` uses this instead of
`allCategories()` when building notification actions. Fewer than 3 used categories still
works — `.take(3)` in `notif_service.dart` already handles a shorter list.

## Track 2 — Release signing + data migration

### Signing

`android/app/build.gradle` currently signs release builds with the debug key
(`signingConfig = signingConfigs.getByName("debug")`, marked with a pre-existing TODO).
This is the likely cause of needing a data migration at all: a debug keystore isn't
guaranteed identical across machines (a locally-built debug APK and a CI-built one can
carry different signatures), so installing a new build can trigger "app not installed —
conflicts with existing package," forcing an uninstall that wipes local app data.

Fix: generate one real release keystore. Wire it into `android/app/build.gradle` via a
gitignored `key.properties` (never committed). Update `.github/workflows/*.yml` (Android
Release workflow) to sign with it using repo secrets, so future GitHub Releases builds
are signed consistently and install as clean updates over any prior release-signed build.

**Keystore custody**: the generated keystore + its passwords must be backed up
somewhere durable (password manager) outside this repo. Losing it means no future
release can ever cleanly update an existing install — the only recovery is asking every
installed user to uninstall and lose their local data again. This is a one-way decision:
once a build ships signed with this key, it's the key for the app's lifetime.

### Data migration (this transition only)

Moving from the current debug-signed install to the new release-signed build still
requires one uninstall/reinstall. Bridge it with the CSV export/import that already
exists (`lib/services/csv_service.dart`, wired into Settings): export before uninstalling,
import after. Covers transactions + categories (categories re-created by name on import
if missing). Does not cover budgets, recurring rules, or the review queue — acceptable
given one day of data; budgets/recurring rules are quick to re-enter manually. A
full-fidelity DB backup/restore file remains on `future_plans.md` for later.

### Distribution

Unchanged: raw APK via the existing GitHub Releases workflow
(`.github/workflows/android-release.yml`). No Play Console / Firebase App Distribution
setup for this round.

## Track 3 — Bank-agnostic SMS detection

### Problem

`isBankSender()` (`lib/parser/patterns.dart`) is a hard allowlist of DLT sender tokens
for ICICI, Kotak, and Indian Bank only. `capture_service.dart:handleSms` calls this as
its first gate — any SMS from an unrecognized sender is dropped immediately
(`CaptureResult.ignored`), before it ever reaches parsing or the review queue. A friend
on SBI/HDFC/Axis/any other bank currently gets nothing captured at all.

A bank-name allowlist in the message body has the same fundamental flaw as a
sender-ID allowlist — it only generalizes to banks someone thought to list. Detection
must not depend on recognizing a specific bank at all.

### Design

Replace the sender-ID gate with a purely content-and-structure-based classifier. A
message is treated as a transaction candidate when **all** of the following hold:

1. **Currency amount present** — `(Rs\.?|INR|₹)\s?[\d,]+(?:\.\d{1,2})?`
2. **Transaction verb present** — one of: debited, credited, debit, credit, withdrawn,
   spent, paid, received
3. **Banking context present** — one of: a/c, acct, account, card, UPI, IMPS, NEFT,
   RTGS, "avl bal", "available balance", "ref no", txn
4. **Sender is not a personal phone number** — Indian bank/DLT alerts always come from
   short alphanumeric business codes (e.g. `AX-ICICIB-S`), never a plain ~10-digit
   mobile number. This is the only sender check retained, and it names no bank.
5. **Not an OTP message** — existing exclusion, retained.

This function replaces `isBankSender()` as the gate in `handleSms`. It supersedes
`_looksTransactional` (folded into the same check, since both now run at the same
point). Known `bankPatterns` regexes (ICICI verified; Kotak/Indian Bank unverified) still
get first attempt at auto-parsing for a full match — auto-store only happens on a
regex match, same as today. Anything that clears the gate but matches no specific
pattern goes to the existing review queue, which already does loose amount-prefill
(`review_screen.dart:_guessPaise`) for fast manual entry.

`isBankSender()` and `_bankSenderTokens` stop being used for gating. They may be
removed or repurposed (e.g. as a hint that skips straight to a matching `BankPattern`
without needing to run the full content classifier) — left to the implementation plan.

### Accepted trade-off

This is deliberately recall-favoring: a non-bank SMS that happens to mention an amount,
a transaction verb, and banking-context words, from a non-personal-number sender,
could occasionally land in the review queue. Cost is one manual dismiss — never an
auto-stored transaction, since auto-store still requires a specific regex match.
Confirmed acceptable; false positives are deleted manually.

### Follow-up (not this round)

Once friends' unmatched SMS accumulate in the review queue, ask them for 2-3 real
anonymized samples per bank to add verified `BankPattern` entries — consistent with the
existing rule that new bank patterns require real samples before being trusted for
auto-store.

## Testing notes for the implementation plan

- `test/parser_test.dart` currently asserts `isBankSender()` directly against specific
  senders. These assertions test the old hard-gate behavior and need to be updated to
  reflect its new (non-gating) role.
- New tests needed: the content classifier (positive cases across amount/verb/context
  combinations, negative cases for OTP and personal-number senders), the ordering fix
  (same-day tie-break), and the top-N-by-usage category ranking.

## Out of scope this round

- Full DB backup/restore file (stays on `future_plans.md`).
- Google Play Console / Firebase App Distribution.
- New verified `BankPattern` entries for any bank beyond ICICI/Kotak/Indian Bank.
- Review-queue UX changes beyond what already exists.
