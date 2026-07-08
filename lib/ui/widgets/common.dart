import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart';
import '../../services/notif_service.dart' show formatPaise;
import '../../state/providers.dart';
import '../theme.dart';
import '../txn_sheet.dart';

class MonthSwitcher extends ConsumerWidget {
  const MonthSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    void shift(int d) => ref.read(selectedMonthProvider.notifier).state =
        DateTime(month.year, month.month + d);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
            onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
        Text(DateFormat('MMMM yyyy').format(month),
            style: Theme.of(context).textTheme.titleMedium),
        IconButton(
            onPressed: () => shift(1), icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class CategoryAvatar extends StatelessWidget {
  final Category? category;
  final double size;

  const CategoryAvatar({super.key, this.category, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = category;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c == null
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : categoryColor(c.colorHex).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      alignment: Alignment.center,
      child: Text(c?.emoji ?? '❓', style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

class TxnTile extends ConsumerWidget {
  final Transaction txn;

  const TxnTile({super.key, required this.txn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoryMapProvider);
    final cat = txn.categoryId == null ? null : cats[txn.categoryId];
    final isDebit = txn.direction == TxnDirection.debit;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CategoryAvatar(category: cat),
      title: Text(txn.merchant,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(cat?.name ?? 'Uncategorized'),
      trailing: Text(
        '${isDebit ? '−' : '+'}${formatPaise(txn.amountPaise)}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: isDebit ? scheme.onSurface : scheme.primary,
        ),
      ),
      onTap: () => showTxnSheet(context, ref, existing: txn),
    );
  }
}

/// Swipe-left-to-delete wrapper around [TxnTile], with an Undo snackbar.
class DismissibleTxnTile extends ConsumerWidget {
  final Transaction txn;

  const DismissibleTxnTile({super.key, required this.txn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    return Dismissible(
      key: ValueKey(txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete),
      ),
      onDismissed: (_) async {
        await (db.delete(db.transactions)..where((t) => t.id.equals(txn.id)))
            .go();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Deleted ${txn.merchant}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () =>
                  db.into(db.transactions).insert(txn.toCompanion(false)),
            ),
          ));
        }
      },
      child: TxnTile(txn: txn),
    );
  }
}
