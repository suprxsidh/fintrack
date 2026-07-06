# FinTrack — Design Spec (2026-07-06)

## What

Android-only personal finance tracker. All data local (SQLite on device). Auto-reads bank
transaction SMS, posts an actionable notification, records the expense. Cashew-inspired
Material You design (inspiration only — Cashew is unlicensed source, no code copied).

User: Suprasidh. Banks: ICICI, Kotak, Indian Bank. Currency: INR. Distribution: sideloaded APK.

## V1 scope

- Auto-capture from bank SMS + notification with quick-categorize action buttons
- Transaction list, manual add/edit, categories (icon + color, seeded defaults)
- Insights: category pie, spending-over-time, month-vs-month
- Budgets: monthly, per-category or overall, progress bars + over-budget state
- Recurring/subscriptions: user-defined rules (e.g. Spotify) + auto-detection of repeated merchant+amount
- Export: CSV (share sheet) and PDF monthly report
- First-run import of historical SMS (last 6 months)

Out of scope v1: multiple accounts/balances, cloud sync, iOS, email parsing, UPI-app notifications.

## Stack

Flutter (stable) + Drift (SQLite). Key packages: `another_telephony` (SMS receive with
background Dart isolate + inbox query for history import), `flutter_local_notifications`
(action buttons), `fl_chart` (charts), `pdf` + `printing` (PDF report), `csv` + `share_plus`
(export), `riverpod` (state).

## Architecture

```
SMS arrives → BroadcastReceiver (pkg) → background Dart isolate
  → SenderFilter (bank sender IDs) → SmsParser (per-bank regex table)
    → parsed:   dedup-check → insert Drift → notification "₹55 RAMESH KUMAR" [Food][Travel][Shopping][More…]
    → unparsed: insert into review_queue → silent notification "1 SMS needs review"
Notification action tap → sets category (background handler, no app open needed)
```

All parsing in Dart (shared between live receiver and history import). No network calls anywhere.

## Parser

Per-bank regex patterns in a Dart table (`lib/parser/patterns.dart`), each yielding:
amount, direction (debit/credit), merchant/counterparty, account tail, date, ref.

Verified sample (ICICI debit):
`ICICI Bank Acct XX123 debited for Rs 55.00 on 06-Jul-26; RAMESH KUMAR credited. UPI:412345678901. ...`

Kotak + Indian Bank patterns drafted from known formats, marked unverified until user
supplies real samples; anything unmatched from a bank sender goes to the review queue,
where the user can correct fields — correction teaches merchant→category mapping.
Merchant memory: last category chosen for a merchant auto-applies next time.

## Data model (Drift tables)

- `transactions`: id, amountPaise (int), direction, merchant, categoryId?, accountTail?,
  txDate, source (sms|manual|import), rawSms?, smsRef?, note?, createdAt
- `categories`: id, name, emoji, colorHex, isSeed
- `budgets`: id, categoryId? (null = overall), amountPaise, active
- `recurring_rules`: id, name, amountPaise?, categoryId, merchantMatch, dueDay, lastSeen
- `review_queue`: id, sender, body, receivedAt, resolved
- `merchant_memory`: merchant (pk), categoryId

Dedup: skip insert if same amountPaise + accountTail + smsRef, or same amount+account within 90s.

## Screens

1. **Home** — month spent total, budget progress bars, recent transactions, FAB manual-add
2. **Transactions** — grouped by day, search + category/date filter, tap to edit, swipe delete
3. **Insights** — category pie, daily/monthly spend line, month-vs-month bars
4. **Budgets** — list + create/edit
5. **Subscriptions** — recurring rules, next-due, auto-detected suggestions
6. **Settings** — export CSV, generate PDF report, manage bank senders, re-run SMS import, review queue

## Error handling

- SMS/notification permission onboarding flow with rationale screens
- Unparsed bank SMS never dropped — review queue
- Duplicate guard as above; import skips already-present smsRefs
- All amounts stored as integer paise (no float money)

## Testing

- Parser unit tests against SMS corpus (`test/parser_test.dart`) — every pattern + negatives (OTP, promo SMS must not match)
- Drift DAO tests (in-memory DB)
- E2E: emulator + `adb emu sms send <sender> <body>` → verify notification + DB row
- Final: `flutter build apk --release`, sideload on user's phone (user step)

## Export

- CSV: all transactions (date, amount, direction, merchant, category, account, note, source) → share sheet. CSV import also supported (doubles as restore, since data is local-only).
- PDF: monthly report — totals, per-category table, budget status → share sheet.
