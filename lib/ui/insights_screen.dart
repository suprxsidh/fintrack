import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../services/notif_service.dart' show formatPaise;
import '../state/providers.dart';
import 'theme.dart';
import 'widgets/common.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byCat = ref.watch(monthSpendByCategoryProvider);
    final cats = ref.watch(categoryMapProvider);
    final total = ref.watch(monthSpentProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const MonthSwitcher(),
        const SizedBox(height: 8),
        if (total == 0)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No spending this month yet')),
          )
        else ...[
          _SectionCard(
            title: 'Where it went',
            child: _CategoryPie(byCat: byCat, cats: cats, total: total),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Through the month',
            child: _CumulativeLine(),
          ),
        ],
        const SizedBox(height: 16),
        _SectionCard(title: 'Last 6 months', child: _MonthlyBars()),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      );
}

class _CategoryPie extends StatelessWidget {
  final Map<int?, int> byCat;
  final Map<int, Category> cats;
  final int total;

  const _CategoryPie(
      {required this.byCat, required this.cats, required this.total});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 3,
              centerSpaceRadius: 48,
              sections: [
                for (final e in entries)
                  PieChartSectionData(
                    value: e.value.toDouble(),
                    color: e.key == null
                        ? scheme.surfaceContainerHigh
                        : categoryColor(cats[e.key]!.colorHex),
                    radius: 36,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final e in entries.take(6))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Text(e.key == null ? '❓' : cats[e.key]!.emoji),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        Text(e.key == null ? 'Uncategorized' : cats[e.key]!.name)),
                Text(
                  '${formatPaise(e.value)} · ${(e.value * 100 / total).round()}%',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CumulativeLine extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(monthTxnsProvider).value ?? const [];
    final month = ref.watch(selectedMonthProvider);
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final perDay = List<int>.filled(daysInMonth + 1, 0);
    for (final t in txns.where((t) => t.direction == TxnDirection.debit)) {
      perDay[t.txDate.day] += t.amountPaise;
    }
    var running = 0;
    final spots = <FlSpot>[const FlSpot(0, 0)];
    for (var d = 1; d <= daysInMonth; d++) {
      running += perDay[d];
      spots.add(FlSpot(d.toDouble(), running / 100));
    }
    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 7,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              dotData: const FlDotData(show: false),
              color: scheme.primary,
              barWidth: 3,
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyBars extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(recentTxnsProvider).value ?? const [];
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final months = [
      for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)
    ];
    final totals = {
      for (final m in months) '${m.year}-${m.month}': 0,
    };
    for (final t in txns.where((t) => t.direction == TxnDirection.debit)) {
      final key = '${t.txDate.year}-${t.txDate.month}';
      if (totals.containsKey(key)) totals[key] = totals[key]! + t.amountPaise;
    }
    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final m = months[v.toInt()];
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(DateFormat('MMM').format(m),
                        style: Theme.of(context).textTheme.labelSmall),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < months.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: totals['${months[i].year}-${months[i].month}']! / 100,
                    color: i == months.length - 1
                        ? scheme.primary
                        : scheme.primaryContainer,
                    width: 22,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
