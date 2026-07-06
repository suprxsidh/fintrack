import 'package:drift/drift.dart' as drift show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../services/notif_service.dart' show formatPaise;
import '../state/providers.dart';
import 'subscriptions_screen.dart';
import 'theme.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider).value ?? const [];
    final cats = ref.watch(categoryMapProvider);
    final byCat = ref.watch(monthSpendByCategoryProvider);
    final total = ref.watch(monthSpentProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'budget_fab',
        onPressed: () => _addBudget(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Budget'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (budgets.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text('No budgets yet. Add one to keep spending honest.')),
            ),
          for (final b in budgets) _BudgetCard(b, cats, byCat, total),
          const SizedBox(height: 8),
          const SubscriptionsSection(),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  Future<void> _addBudget(BuildContext context, WidgetRef ref) async {
    final cats = ref.read(categoriesProvider).value ?? const [];
    final amount = TextEditingController();
    int? categoryId; // null = overall
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int?>(
                initialValue: categoryId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Overall')),
                  for (final c in cats)
                    DropdownMenuItem(
                        value: c.id, child: Text('${c.emoji} ${c.name}')),
                ],
                onChanged: (v) => setState(() => categoryId = v),
                decoration: const InputDecoration(labelText: 'Scope'),
              ),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Monthly limit', prefixText: '₹ '),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    final rupees = int.tryParse(amount.text.trim());
    if (saved != true || rupees == null || rupees <= 0) return;
    final db = ref.read(dbProvider);
    await db.into(db.budgets).insert(BudgetsCompanion.insert(
        categoryId: drift.Value(categoryId), amountPaise: rupees * 100));
  }
}

class _BudgetCard extends ConsumerWidget {
  final Budget budget;
  final Map<int, Category> cats;
  final Map<int?, int> byCat;
  final int total;

  const _BudgetCard(this.budget, this.cats, this.byCat, this.total);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = budget.categoryId == null ? null : cats[budget.categoryId];
    final spent =
        budget.categoryId == null ? total : (byCat[budget.categoryId] ?? 0);
    final over = spent > budget.amountPaise;
    final frac =
        (spent / (budget.amountPaise == 0 ? 1 : budget.amountPaise)).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(cat == null ? '🌐 Overall' : '${cat.emoji} ${cat.name}',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    final db = ref.read(dbProvider);
                    await (db.delete(db.budgets)
                          ..where((x) => x.id.equals(budget.id)))
                        .go();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: frac,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
              color: over
                  ? scheme.error
                  : cat == null
                      ? scheme.primary
                      : categoryColor(cat.colorHex),
              backgroundColor: scheme.surfaceContainerHigh,
            ),
            const SizedBox(height: 8),
            Text(
              over
                  ? '${formatPaise(spent - budget.amountPaise)} over the ${formatPaise(budget.amountPaise)} limit'
                  : '${formatPaise(spent)} of ${formatPaise(budget.amountPaise)} · ${formatPaise(budget.amountPaise - spent)} left',
              style: TextStyle(
                  color: over ? scheme.error : scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
