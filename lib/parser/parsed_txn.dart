import '../data/db.dart';

class ParsedTxn {
  final int amountPaise;
  final TxnDirection direction;
  final String merchant;
  final String? accountTail;
  final DateTime txDate;
  final String? ref;
  final String bank;

  const ParsedTxn({
    required this.amountPaise,
    required this.direction,
    required this.merchant,
    required this.txDate,
    required this.bank,
    this.accountTail,
    this.ref,
  });
}
