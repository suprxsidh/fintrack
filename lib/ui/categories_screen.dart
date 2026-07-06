import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../state/providers.dart';
import 'widgets/common.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final c in cats)
            ListTile(
              leading: CategoryAvatar(category: c),
              title: Text(c.name),
              onTap: () => _edit(context, ref, c),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, ref, c),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Category? c) async {
    final name = TextEditingController(text: c?.name ?? '');
    final emoji = TextEditingController(text: c?.emoji ?? '🏷️');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c == null ? 'New category' : 'Edit category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emoji,
              decoration: const InputDecoration(labelText: 'Emoji'),
              maxLength: 2,
            ),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;
    final db = ref.read(dbProvider);
    if (c == null) {
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: name.text.trim(),
          emoji: emoji.text.trim().isEmpty ? '🏷️' : emoji.text.trim(),
          colorHex: '78909C'));
    } else {
      await (db.update(db.categories)..where((x) => x.id.equals(c.id))).write(
          CategoriesCompanion(
              name: Value(name.text.trim()),
              emoji: Value(emoji.text.trim().isEmpty ? c.emoji : emoji.text.trim())));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Category c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text(
            'Transactions keep their history but become Uncategorized.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(dbProvider);
    // detach references first: FK has no cascade
    await (db.update(db.transactions)
          ..where((t) => t.categoryId.equals(c.id)))
        .write(const TransactionsCompanion(categoryId: Value(null)));
    await (db.delete(db.merchantMemory)
          ..where((m) => m.categoryId.equals(c.id)))
        .go();
    await (db.delete(db.budgets)..where((b) => b.categoryId.equals(c.id))).go();
    await (db.delete(db.categories)..where((x) => x.id.equals(c.id))).go();
  }
}
