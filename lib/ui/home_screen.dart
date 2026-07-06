import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notif_service.dart' show formatPaise;
import '../state/providers.dart';
import 'theme.dart';
import 'widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spent = ref.watch(monthSpentProvider);
    final txns = ref.watch(monthTxnsProvider).value ?? const [];
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const MonthSwitcher(),
        const SizedBox(height: 8),
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text('Spent this month',
                    style: TextStyle(color: scheme.onPrimaryContainer)),
                const SizedBox(height: 4),
                Text(
                  formatPaise(spent),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _BudgetSummary(),
        const SizedBox(height: 16),
        Text('Recent', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (txns.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No transactions yet this month')),
          )
        else
          Card(
            child: Column(
              children: [for (final t in txns.take(10)) TxnTile(txn: t)],
            ),
          ),
      ],
    );
  }
}

class _BudgetSummary extends ConsumerWidget {
  const _BudgetSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider).value ?? const [];
    if (budgets.isEmpty) return const SizedBox.shrink();
    final byCat = ref.watch(monthSpendByCategoryProvider);
    final cats = ref.watch(categoryMapProvider);
    final total = ref.watch(monthSpentProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Budgets', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final b in budgets)
              _BudgetBar(
                label: b.categoryId == null
                    ? 'Overall'
                    : '${cats[b.categoryId]?.emoji ?? ''} ${cats[b.categoryId]?.name ?? '?'}',
                spent: b.categoryId == null ? total : (byCat[b.categoryId] ?? 0),
                limit: b.amountPaise,
                color: b.categoryId == null
                    ? Theme.of(context).colorScheme.primary
                    : categoryColor(cats[b.categoryId]?.colorHex ?? '78909C'),
              ),
          ],
        ),
      ),
    );
  }
}

class _BudgetBar extends StatelessWidget {
  final String label;
  final int spent;
  final int limit;
  final Color color;

  const _BudgetBar(
      {required this.label,
      required this.spent,
      required this.limit,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final over = spent > limit;
    final frac = limit == 0 ? 1.0 : (spent / limit).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(
                '${formatPaise(spent)} / ${formatPaise(limit)}',
                style: TextStyle(
                    color: over ? scheme.error : scheme.onSurfaceVariant,
                    fontWeight: over ? FontWeight.w600 : null),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: frac,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            color: over ? scheme.error : color,
            backgroundColor: scheme.surfaceContainerHigh,
          ),
        ],
      ),
    );
  }
}
