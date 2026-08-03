import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../parser/sms_parser.dart' show parseAmountPaise;
import '../state/providers.dart';
import 'txn_sheet.dart';

/// Bank SMS the parser couldn't handle. Saving one as a transaction resolves
/// it and (via the sheet) teaches merchant memory for next time.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(reviewQueueProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Needs review')),
      body: queue.isEmpty
          ? const Center(child: Text('All caught up 🎉'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: queue.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = queue[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.sender} · ${DateFormat('d MMM, HH:mm').format(item.receivedAt)}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(item.body),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _resolve(ref, item.id),
                              child: const Text('Dismiss'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () async {
                                final saved = await showTxnSheet(context, ref,
                                    prefillPaise: _guessPaise(item.body),
                                    prefillMerchant:
                                        _guessMerchant(item.body));
                                if (saved == true) _resolve(ref, item.id);
                              },
                              child: const Text('Add expense'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _resolve(WidgetRef ref, int id) {
    final db = ref.read(dbProvider);
    (db.update(db.reviewQueue)..where((r) => r.id.equals(id)))
        .write(const ReviewQueueCompanion(resolved: Value(true)));
  }

  /// Loose amount guess for prefill: first ₹/Rs/INR number in the body.
  static int? _guessPaise(String body) {
    final m = RegExp(r'(?:Rs\.?|INR|₹)\s?([\d,]+(?:\.\d{1,2})?)',
            caseSensitive: false)
        .firstMatch(body);
    return m == null ? null : parseAmountPaise(m.group(1)!);
  }

  /// Loose merchant/payee guess for prefill: the trailing name in a
  /// `UPI/<type>/<ref>/<name>` segment (e.g. Axis's "UPI/P2M/6214.../NAME").
  /// ICICI/Kotak/IndianBank UPI refs don't use this double-slash shape
  /// (they're "UPI:123" or "UPI Ref 123"), so this never fires for them —
  /// returns null rather than guessing wrong when the body doesn't match.
  static String? _guessMerchant(String body) {
    final m = RegExp(r'UPI/[^/\n]+/[^/\n]+/([^\n]+?)(?=\n|\s+Not you\b|$)',
            caseSensitive: false)
        .firstMatch(body);
    final name = m?.group(1)?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }
}
