import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/daos.dart';
import '../data/db.dart';
import '../state/providers.dart';
import 'theme.dart';

/// Add (existing == null) or edit a transaction. Handles category learning
/// through AppDb.setCategory so notifications and manual edits teach the
/// same merchant memory. Resolves true when the user saved.
Future<bool?> showTxnSheet(BuildContext context, WidgetRef ref,
    {Transaction? existing, String? prefillMerchant, int? prefillPaise}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TxnForm(
      existing: existing,
      prefillMerchant: prefillMerchant,
      prefillPaise: prefillPaise,
    ),
  );
}

class _TxnForm extends ConsumerStatefulWidget {
  final Transaction? existing;
  final String? prefillMerchant;
  final int? prefillPaise;

  const _TxnForm({this.existing, this.prefillMerchant, this.prefillPaise});

  @override
  ConsumerState<_TxnForm> createState() => _TxnFormState();
}

class _TxnFormState extends ConsumerState<_TxnForm> {
  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _note;
  late TxnDirection _direction;
  late DateTime _date;
  int? _categoryId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(
        text: e != null
            ? (e.amountPaise / 100).toStringAsFixed(2)
            : widget.prefillPaise != null
                ? (widget.prefillPaise! / 100).toStringAsFixed(2)
                : '');
    _merchant = TextEditingController(
        text: e?.merchant ?? widget.prefillMerchant ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _direction = e?.direction ?? TxnDirection.debit;
    _date = e?.txDate ?? DateTime.now();
    _categoryId = e?.categoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _paise {
    final v = double.tryParse(_amount.text.replaceAll(',', ''));
    if (v == null || v <= 0) return null;
    return (v * 100).round();
  }

  Future<void> _save() async {
    final paise = _paise;
    final merchant = _merchant.text.trim();
    if (paise == null || merchant.isEmpty) return;
    final db = ref.read(dbProvider);
    final e = widget.existing;
    int id;
    if (e == null) {
      id = await db.insertTransaction(TransactionsCompanion.insert(
        amountPaise: paise,
        direction: _direction,
        merchant: merchant,
        txDate: _date,
        source: TxnSource.manual,
        note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
      ));
    } else {
      id = e.id;
      await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          amountPaise: Value(paise),
          direction: Value(_direction),
          merchant: Value(merchant),
          txDate: Value(_date),
          note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
        ),
      );
    }
    if (_categoryId != null && _categoryId != e?.categoryId) {
      await db.setCategory(id, _categoryId!);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(dbProvider);
    await (db.delete(db.transactions)
          ..where((t) => t.id.equals(widget.existing!.id)))
        .go();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).value ?? const [];
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    widget.existing == null
                        ? 'Add transaction'
                        : 'Edit transaction',
                    style: Theme.of(context).textTheme.titleLarge),
                if (widget.existing != null)
                  TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error),
                    child: const Text('Delete'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: widget.existing == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: Theme.of(context).textTheme.headlineMedium,
              decoration: const InputDecoration(prefixText: '₹ ', hintText: '0.00'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<TxnDirection>(
              segments: const [
                ButtonSegment(
                    value: TxnDirection.debit,
                    label: Text('Expense'),
                    icon: Icon(Icons.arrow_upward)),
                ButtonSegment(
                    value: TxnDirection.credit,
                    label: Text('Income'),
                    icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _merchant,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Merchant / person'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in cats)
                  ChoiceChip(
                    avatar: Text(c.emoji),
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    selectedColor:
                        categoryColor(c.colorHex).withValues(alpha: 0.3),
                    onSelected: (_) => setState(() =>
                        _categoryId = _categoryId == c.id ? null : c.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(DateFormat('d MMM yyyy').format(_date)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(widget.existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
