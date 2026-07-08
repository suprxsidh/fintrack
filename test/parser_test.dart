import 'package:fintrack/data/db.dart';
import 'package:fintrack/parser/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Real sample from user's phone, 2026-07-06. The one VERIFIED pattern.
const icici = 'ICICI Bank Acct XX123 debited for Rs 55.00 on 06-Jul-26; '
    'RAMESH KUMAR credited. UPI:412345678901. Call 18002662 for dispute. '
    'SMS BLOCK 106 to 9215676766.';

void main() {
  group('bank sender detection', () {
    test('accepts DLT sender ids', () {
      for (final s in ['AX-ICICIB-S', 'JD-KOTAKB', 'CP-INDBNK-S', 'ICICIT']) {
        expect(isBankSender(s), isTrue, reason: s);
      }
    });
    test('rejects non-bank senders', () {
      for (final s in ['AX-SWIGGY', 'VM-AMAZON', '+919812345678', 'DM-AIRTEL']) {
        expect(isBankSender(s), isFalse, reason: s);
      }
    });
  });

  group('ICICI (verified sample)', () {
    test('parses UPI debit exactly', () {
      final t = SmsParser.parse('AX-ICICIB-S', icici)!;
      expect(t.amountPaise, 5500);
      expect(t.direction, TxnDirection.debit);
      expect(t.merchant, 'RAMESH KUMAR');
      expect(t.accountTail, '123');
      expect(t.txDate, DateTime(2026, 7, 6));
      expect(t.ref, '412345678901');
      expect(t.bank, 'ICICI');
    });
    test('parses amount with commas', () {
      final t = SmsParser.parse(
          'AX-ICICIB-S',
          'ICICI Bank Acct XX123 debited for Rs 1,299.50 on 06-Jul-26; '
          'AMAZON PAY credited. UPI:99. blah')!;
      expect(t.amountPaise, 129950);
    });
  });

  group('drafted patterns (unverified formats)', () {
    test('kotak upi debit', () {
      final t = SmsParser.parse(
          'JD-KOTAKB',
          'Sent Rs.199.00 from Kotak Bank AC X4321 to spotify@axisb on '
          '06-07-26.UPI Ref 655315924199. Not you? kotak.com/fraud')!;
      expect(t.amountPaise, 19900);
      expect(t.direction, TxnDirection.debit);
      expect(t.merchant, 'spotify@axisb');
      expect(t.accountTail, '4321');
      expect(t.txDate, DateTime(2026, 7, 6));
      expect(t.ref, '655315924199');
    });
    test('kotak credit', () {
      final t = SmsParser.parse(
          'JD-KOTAKB',
          'Received Rs.2,000.00 in your Kotak Bank AC X4321 from friend@okici '
          'on 06-07-26.UPI Ref:88.')!;
      expect(t.amountPaise, 200000);
      expect(t.direction, TxnDirection.credit);
    });
    test('indian bank debit', () {
      final t = SmsParser.parse(
          'CP-INDBNK-S',
          'Rs. 350.00 debited from A/c *5678 on 06-07-2026 to VPA '
          'zomato@paytm. UPI Ref 655319999. Indian Bank')!;
      expect(t.amountPaise, 35000);
      expect(t.merchant, 'zomato@paytm');
      expect(t.accountTail, '5678');
    });
    test('icici card spend', () {
      final t = SmsParser.parse(
          'AX-ICICIB-S',
          'INR 450.00 spent on ICICI Bank Card XX9005 on 06-Jul-26 at SWIGGY. '
          'Avl Lmt: INR 1,00,000.')!;
      expect(t.amountPaise, 45000);
      expect(t.merchant, 'SWIGGY');
    });
  });

  group('negatives — must not parse', () {
    test('otp sms', () {
      expect(
          SmsParser.parse('AX-ICICIB-S',
              '482913 is the OTP for txn of Rs 55.00. Do not share.'),
          isNull);
    });
    test('promo', () {
      expect(
          SmsParser.parse('AX-ICICIB-S',
              'Get 10% cashback up to Rs 200 on your next UPI payment!'),
          isNull);
    });
    test('balance enquiry', () {
      expect(
          SmsParser.parse(
              'AX-ICICIB-S', 'Avl Bal in Acct XX123 is Rs 12,345.67.'),
          isNull);
    });
    test('non-bank sender with txn-looking text', () {
      expect(SmsParser.parse('VM-AMAZON', icici), isNull);
    });
  });

  group('helpers', () {
    test('parseIndianDate variants', () {
      expect(parseIndianDate('06-Jul-26'), DateTime(2026, 7, 6));
      expect(parseIndianDate('06-07-26'), DateTime(2026, 7, 6));
      expect(parseIndianDate('06/07/2026'), DateTime(2026, 7, 6));
      expect(parseIndianDate('garbage'), isNull);
    });
    test('parseAmountPaise integer math', () {
      expect(parseAmountPaise('55.00'), 5500);
      expect(parseAmountPaise('1,234.5'), 123450);
      expect(parseAmountPaise('99'), 9900);
      expect(parseAmountPaise('abc'), isNull);
    });
  });

  group('looksLikeTransactionSms (bank-agnostic detection)', () {
    test('unrecognized business sender with transaction wording passes', () {
      expect(
          looksLikeTransactionSms(
              'VM-SOMEBANK', 'Rs 500 debited from A/c XX1234 via UPI'),
          isTrue);
    });
    test('known bank sender with a real sample still passes', () {
      expect(looksLikeTransactionSms('AX-ICICIB-S', icici), isTrue);
    });
    test('personal phone number sender rejected even with transaction wording',
        () {
      expect(
          looksLikeTransactionSms(
              '+919812345678', 'Rs 500 debited from A/c XX1234 via UPI'),
          isFalse);
    });
    test('otp rejected', () {
      expect(
          looksLikeTransactionSms(
              'AX-ICICIB-S', '482913 is the OTP for txn of Rs 55.00.'),
          isFalse);
    });
    test('promo without a direction verb rejected', () {
      expect(
          looksLikeTransactionSms('AX-ICICIB-S',
              'Get 10% cashback up to Rs 200 on your next UPI payment!'),
          isFalse);
    });
    test('balance enquiry rejected', () {
      expect(
          looksLikeTransactionSms(
              'AX-ICICIB-S', 'Avl Bal in Acct XX123 is Rs 12,345.67.'),
          isFalse);
    });
  });
}
