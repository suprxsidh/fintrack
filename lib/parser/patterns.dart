import '../data/db.dart';

/// One bank-SMS regex pattern. Group indices map extracted fields; any index
/// can be null when the pattern doesn't capture that field.
class BankPattern {
  final String bank;
  final TxnDirection direction;
  final RegExp regex;
  final int amountGroup;
  final int? merchantGroup;
  final int? tailGroup;
  final int? dateGroup;
  final int? refGroup;

  /// Used when [merchantGroup] is null (e.g. plain credit alerts).
  final String fallbackMerchant;

  const BankPattern({
    required this.bank,
    required this.direction,
    required this.regex,
    required this.amountGroup,
    this.merchantGroup,
    this.tailGroup,
    this.dateGroup,
    this.refGroup,
    this.fallbackMerchant = 'Unknown',
  });
}

final bankPatterns = <BankPattern>[
  // ICICI UPI debit — VERIFIED against a real sample 2026-07-06 (details anonymized):
  // "ICICI Bank Acct XX123 debited for Rs 55.00 on 06-Jul-26; RAMESH KUMAR
  //  credited. UPI:412345678901. Call 18002662 for dispute."
  BankPattern(
    bank: 'ICICI',
    direction: TxnDirection.debit,
    regex: RegExp(
        r'ICICI Bank Acct XX(\w+) debited for Rs ([\d,]+(?:\.\d{1,2})?) on (\d{2}-[A-Za-z]{3}-\d{2});\s*(.+?) credited(?:\.\s*UPI:(\d+))?',
        caseSensitive: false),
    tailGroup: 1,
    amountGroup: 2,
    dateGroup: 3,
    merchantGroup: 4,
    refGroup: 5,
  ),
  // ICICI account credit — UNVERIFIED draft:
  // "Your ICICI Bank Acct XX123 is credited with Rs 500.00 on 06-Jul-26 from
  //  NAME. UPI:1234"
  BankPattern(
    bank: 'ICICI',
    direction: TxnDirection.credit,
    regex: RegExp(
        r'ICICI Bank Acc(?:oun)?t XX(\w+) (?:is )?credited with (?:Rs\.?|INR) ?([\d,]+(?:\.\d{1,2})?) on (\d{2}-[A-Za-z]{3}-\d{2})(?:.*?(?:from|by)[ :](.+?)[.;])?(?:.*UPI[: ](\d+))?',
        caseSensitive: false),
    tailGroup: 1,
    amountGroup: 2,
    dateGroup: 3,
    merchantGroup: 4,
    refGroup: 5,
    fallbackMerchant: 'Credit',
  ),
  // ICICI card spend — UNVERIFIED draft:
  // "INR 450.00 spent on ICICI Bank Card XX9005 on 06-Jul-26 at SWIGGY. Avl
  //  Lmt: ..."
  BankPattern(
    bank: 'ICICI',
    direction: TxnDirection.debit,
    regex: RegExp(
        r'(?:Rs\.?|INR) ?([\d,]+(?:\.\d{1,2})?) spent (?:on|using) ICICI Bank Card XX(\w+) on (\d{2}-[A-Za-z]{3}-\d{2}) (?:at|on) (.+?)\.',
        caseSensitive: false),
    amountGroup: 1,
    tailGroup: 2,
    dateGroup: 3,
    merchantGroup: 4,
  ),
  // Kotak UPI debit — UNVERIFIED draft:
  // "Sent Rs.55.00 from Kotak Bank AC X1234 to name@upi on 06-07-26.UPI Ref
  //  412345678901. Not you, kotak.com/fraud"
  BankPattern(
    bank: 'Kotak',
    direction: TxnDirection.debit,
    regex: RegExp(
        r'Sent (?:Rs\.?|INR) ?([\d,]+(?:\.\d{1,2})?) from Kotak Bank AC X(\w+) to (.+?) on (\d{2}-\d{2}-\d{2,4})\.?\s*UPI Ref[: ]?(\d+)',
        caseSensitive: false),
    amountGroup: 1,
    tailGroup: 2,
    merchantGroup: 3,
    dateGroup: 4,
    refGroup: 5,
  ),
  // Kotak credit — UNVERIFIED draft:
  // "Received Rs.500.00 in your Kotak Bank AC X1234 from name@upi on
  //  06-07-26.UPI Ref:123."
  BankPattern(
    bank: 'Kotak',
    direction: TxnDirection.credit,
    regex: RegExp(
        r'Received (?:Rs\.?|INR) ?([\d,]+(?:\.\d{1,2})?) in your Kotak Bank AC X(\w+) from (.+?) on (\d{2}-\d{2}-\d{2,4})\.?\s*UPI Ref[: ]?(\d+)',
        caseSensitive: false),
    amountGroup: 1,
    tailGroup: 2,
    merchantGroup: 3,
    dateGroup: 4,
    refGroup: 5,
  ),
  // Indian Bank debit — UNVERIFIED draft:
  // "Rs. 55.00 debited from A/c *1234 on 06-07-2026 to VPA name@upi Ref
  //  412345678901. Indian Bank"
  BankPattern(
    bank: 'IndianBank',
    direction: TxnDirection.debit,
    regex: RegExp(
        r'(?:Rs\.?|INR) ?([\d,]+(?:\.\d{1,2})?) (?:has been )?debited from (?:your )?A/c \*?(\w+) on (\d{2}[-/]\d{2}[-/]\d{2,4})(?: to (?:VPA )?(\S+?)(?=[.\s]|$))?(?:[.\s]+(?:UPI )?Ref[.: ]?(\d+))?',
        caseSensitive: false),
    amountGroup: 1,
    tailGroup: 2,
    dateGroup: 3,
    merchantGroup: 4,
    refGroup: 5,
  ),
  // Indian Bank credit — UNVERIFIED draft.
  BankPattern(
    bank: 'IndianBank',
    direction: TxnDirection.credit,
    regex: RegExp(
        r'(?:Rs\.?|INR) ?([\d,]+(?:\.\d{1,2})?) (?:has been )?credited to (?:your )?A/c \*?(\w+) on (\d{2}[-/]\d{2}[-/]\d{2,4})(?: (?:from|by) (\S+?)(?=[.\s]|$))?(?:[.\s]+(?:UPI )?Ref[.: ]?(\d+))?',
        caseSensitive: false),
    amountGroup: 1,
    tailGroup: 2,
    dateGroup: 3,
    merchantGroup: 4,
    refGroup: 5,
    fallbackMerchant: 'Credit',
  ),
];

/// DLT sender IDs look like "AX-ICICIB-S", "JD-KOTAKB", "CP-INDBNK-S".
final _bankSenderTokens = RegExp(
    r'ICICIB|ICICIT|KOTAKB|KOTAKM|INDBNK|INDBK|INDIANBK',
    caseSensitive: false);

bool isBankSender(String sender) => _bankSenderTokens.hasMatch(sender);

final _personalNumber = RegExp(r'^\+?(?:91)?\d{10}$');

/// True for a plain Indian mobile number. Bank/DLT alerts always come from
/// short alphanumeric business codes, never a personal number — this is the
/// only sender signal the generalized detector below relies on, and it
/// names no bank, so it works for any bank without a maintained allowlist.
bool _isPersonalNumber(String sender) =>
    _personalNumber.hasMatch(sender.trim());

final _amountPattern =
    RegExp(r'(?:rs\.?|inr|₹)\s?[\d,]+(?:\.\d{1,2})?', caseSensitive: false);
final _directionVerbs = RegExp(
    r'\b(debited|credited|debit|credit|withdrawn|spent|paid|received|sent)\b',
    caseSensitive: false);
final _bankContext = RegExp(
    r'\b(a/c|acct|account|card|upi|imps|neft|rtgs|ref no|txn)\b',
    caseSensitive: false);

/// True if [body] reads like a bank transaction alert, regardless of which
/// bank sent it or whether [sender] is a recognized bank sender ID. This is
/// the entry gate for capture: auto-store still requires a full match
/// against a known [BankPattern] (see [isBankSender], used inside
/// `SmsParser.parse`) — this function only decides whether an unmatched
/// message reaches the review queue instead of being dropped.
bool looksLikeTransactionSms(String sender, String body) {
  if (_isPersonalNumber(sender)) return false;
  final b = body.toLowerCase();
  if (b.contains('otp')) return false;
  if (b.contains('avl bal') || b.contains('available balance')) return false;
  return _amountPattern.hasMatch(b) &&
      _directionVerbs.hasMatch(b) &&
      _bankContext.hasMatch(b);
}
