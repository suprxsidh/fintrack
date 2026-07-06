import 'package:drift/drift.dart' as drift show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../services/notif_service.dart' show formatPaise;
import '../services/recurring_detector.dart';
import '../state/providers.dart';

/// Recurring section shown inside the Budgets tab: tracked rules with
/// next-due dates, plus auto-detected suggestions with one-tap tracking.
class SubscriptionsSection extends ConsumerWidget {
  const SubscriptionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider).value ?? const [];
    final recent = ref.watch(recentTxnsProvider).value ?? const [];
    final suggestions = RecurringDetector.suggest(
      recent,
      alreadyTracked: {for (final r in rules) r.merchantMatch.toUpperCase()},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Subscriptions & recurring',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (rules.isEmpty && suggestions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Nothing recurring yet. Repeated same-amount payments show up here automatically.'),
            ),
          ),
        for (final r in rules) _RuleTile(rule: r),
        for (final s in suggestions.take(3)) _SuggestionCard(s: s),
      ],
    );
  }
}

DateTime nextDue(int dueDay) {
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, dueDay);
  return thisMonth.isBefore(DateTime(now.year, now.month, now.day))
      ? DateTime(now.year, now.month + 1, dueDay)
      : thisMonth;
}

class _RuleTile extends ConsumerWidget {
  final RecurringRule rule;

  const _RuleTile({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = nextDue(rule.dueDay);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.autorenew),
        title: Text(rule.name),
        subtitle: Text('Due ${DateFormat('d MMM').format(due)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rule.amountPaise != null)
              Text(formatPaise(rule.amountPaise!),
                  style: Theme.of(context).textTheme.titleSmall),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () async {
                final db = ref.read(dbProvider);
                await (db.delete(db.recurringRules)
                      ..where((r) => r.id.equals(rule.id)))
                    .go();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  final RecurringSuggestion s;

  const _SuggestionCard({required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.lightbulb_outline),
        title: Text(s.merchant),
        subtitle: Text(
            'Looks recurring: ${formatPaise(s.amountPaise)} × ${s.occurrences}'),
        trailing: FilledButton.tonal(
          child: const Text('Track'),
          onPressed: () async {
            final db = ref.read(dbProvider);
            await db.into(db.recurringRules).insert(
                  RecurringRulesCompanion.insert(
                    name: s.merchant,
                    amountPaise: drift.Value(s.amountPaise),
                    merchantMatch: s.merchant,
                    dueDay: s.dueDay,
                  ),
                );
          },
        ),
      ),
    );
  }
}
