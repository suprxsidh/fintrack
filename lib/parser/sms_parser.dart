import 'parsed_txn.dart';
import 'patterns.dart';

export 'patterns.dart' show isBankSender;

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Parses "06-Jul-26", "06-07-26", "06-07-2026", "06/07/2026" (day first).
/// Returns null on anything else.
DateTime? parseIndianDate(String raw) {
  final parts = raw.split(RegExp(r'[-/]'));
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final yearRaw = int.tryParse(parts[2]);
  if (day == null || yearRaw == null) return null;
  final year = yearRaw < 100 ? 2000 + yearRaw : yearRaw;
  final month = int.tryParse(parts[1]) ?? _months[parts[1].toLowerCase()];
  if (month == null || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  return DateTime(year, month, day);
}

/// "1,234.50" → 123450 paise. Integer math only.
int? parseAmountPaise(String raw) {
  final clean = raw.replaceAll(',', '');
  final dot = clean.indexOf('.');
  final rupeesStr = dot == -1 ? clean : clean.substring(0, dot);
  final paiseStr = dot == -1 ? '' : clean.substring(dot + 1).padRight(2, '0');
  final rupees = int.tryParse(rupeesStr);
  if (rupees == null) return null;
  final paise = paiseStr.isEmpty ? 0 : int.tryParse(paiseStr.substring(0, 2));
  if (paise == null) return null;
  return rupees * 100 + paise;
}

class SmsParser {
  /// Returns the parsed transaction, or null when [body] is not a
  /// transaction SMS (OTP, promo, balance...) or [sender] is not a bank.
  static ParsedTxn? parse(String sender, String body, {DateTime? received}) {
    if (!isBankSender(sender)) return null;
    for (final p in bankPatterns) {
      final m = p.regex.firstMatch(body);
      if (m == null) continue;
      final amount = parseAmountPaise(m.group(p.amountGroup)!.trim());
      if (amount == null || amount == 0) continue;
      DateTime? date;
      if (p.dateGroup != null && m.group(p.dateGroup!) != null) {
        date = parseIndianDate(m.group(p.dateGroup!)!);
      }
      final merchantRaw = p.merchantGroup == null
          ? null
          : m.group(p.merchantGroup!)?.trim().replaceAll(RegExp(r'\s+'), ' ');
      return ParsedTxn(
        amountPaise: amount,
        direction: p.direction,
        merchant: (merchantRaw == null || merchantRaw.isEmpty)
            ? p.fallbackMerchant
            : merchantRaw,
        accountTail: p.tailGroup == null ? null : m.group(p.tailGroup!),
        txDate: date ?? received ?? DateTime.now(),
        ref: p.refGroup == null ? null : m.group(p.refGroup!),
        bank: p.bank,
      );
    }
    return null;
  }
}
