import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../state/providers.dart';
import 'widgets/common.dart';

final _searchProvider = StateProvider<String>((_) => '');
final _filterCatProvider = StateProvider<int?>((_) => null);

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(monthTxnsProvider).value ?? const [];
    final query = ref.watch(_searchProvider).toLowerCase();
    final filterCat = ref.watch(_filterCatProvider);
    final cats = ref.watch(categoriesProvider).value ?? const [];

    final txns = all.where((t) {
      if (filterCat != null && t.categoryId != filterCat) return false;
      if (query.isNotEmpty &&
          !t.merchant.toLowerCase().contains(query) &&
          !(t.note ?? '').toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();

    final byDay = <DateTime, List<Transaction>>{};
    for (final t in txns) {
      final day = DateTime(t.txDate.year, t.txDate.month, t.txDate.day);
      byDay.putIfAbsent(day, () => []).add(t);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        const MonthSwitcher(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search merchant or note',
              isDense: true,
            ),
            onChanged: (v) => ref.read(_searchProvider.notifier).state = v,
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: Text(c.emoji),
                    label: Text(c.name),
                    selected: filterCat == c.id,
                    onSelected: (_) => ref
                        .read(_filterCatProvider.notifier)
                        .state = filterCat == c.id ? null : c.id,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: txns.isEmpty
              ? const Center(child: Text('Nothing here'))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    for (final day in days) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text(
                          DateFormat('EEEE, d MMM').format(day),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      for (final t in byDay[day]!) _DismissibleTxn(txn: t),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _DismissibleTxn extends ConsumerWidget {
  final Transaction txn;

  const _DismissibleTxn({required this.txn});

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
