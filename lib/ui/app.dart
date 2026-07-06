import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'budgets_screen.dart';
import 'home_screen.dart';
import 'insights_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'transactions_screen.dart';
import 'txn_sheet.dart';

class FinTrackApp extends StatelessWidget {
  const FinTrackApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FinTrack',
        debugShowCheckedModeBanner: false,
        theme: finTheme(Brightness.light),
        darkTheme: finTheme(Brightness.dark),
        home: const _Shell(),
      );
}

class _Shell extends ConsumerStatefulWidget {
  const _Shell();

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: const [
            HomeScreen(),
            TransactionsScreen(),
            InsightsScreen(),
            BudgetsScreen(),
            SettingsScreen(),
          ],
        ),
      ),
      floatingActionButton: _tab <= 1
          ? FloatingActionButton(
              onPressed: () => showTxnSheet(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Insights'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Budgets'),
          NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
