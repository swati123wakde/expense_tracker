import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/category_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../providers/categories_provider.dart';
import '../common/common_widgets.dart';
import '../common/pickers.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  TransactionType _type = TransactionType.expense;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CategoriesProvider>();
    final active = p.active(_type);
    final archived = p.archived.where((c) => c.type == _type).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => CategoryEditorSheet.show(context, type: _type),
        icon: const Icon(Icons.add),
        label: const Text('Category'),
      ),
      body: ListView(
        padding: Spacing.page,
        children: [
          SegmentedButton<TransactionType>(
            segments: const [
              ButtonSegment(value: TransactionType.expense, label: Text('Expense')),
              ButtonSegment(value: TransactionType.income, label: Text('Income')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (final c in active) _tile(context, c),
              ],
            ),
          ),
          if (archived.isNotEmpty) ...[
            const SectionHeader(title: 'Archived'),
            Card(child: Column(children: [for (final c in archived) _tile(context, c)])),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, CategoryEntity c) => ListTile(
        leading: CategoryAvatar(icon: c.icon, color: c.color, size: 38),
        title: Text(c.name),
        subtitle: Text(c.isCustom ? 'Custom' : 'Built-in'),
        trailing: IconButton(
          tooltip: c.archived ? 'Unarchive' : 'Archive',
          icon: Icon(c.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
          onPressed: () => context.read<CategoriesProvider>().setArchived(c.id, !c.archived),
        ),
        onTap: () => CategoryEditorSheet.show(context, existing: c, type: c.type),
      );
}

class CategoryEditorSheet extends StatefulWidget {
  const CategoryEditorSheet({super.key, this.existing, required this.type});

  final CategoryEntity? existing;
  final TransactionType type;

  static Future<void> show(BuildContext context, {CategoryEntity? existing, required TransactionType type}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => CategoryEditorSheet(existing: existing, type: type),
      );

  @override
  State<CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<CategoryEditorSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late TransactionType _type = widget.existing?.type ?? widget.type;
  late String _icon = widget.existing?.icon ?? 'star';
  late int _color = widget.existing?.color ?? AppPalette.colors.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Enter a category name', error: true);
      return;
    }
    final p = context.read<CategoriesProvider>();
    final e = widget.existing;
    if (e == null) {
      await p.create(name: name, type: _type, icon: _icon, color: _color);
    } else {
      await p.update(e.copyWith(name: name, type: _type, icon: _icon, color: _color));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e == null ? 'New category' : 'Edit category', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                CategoryAvatar(icon: _icon, color: _color, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('categoryNameField'),
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (e == null || e.isCustom)
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(value: TransactionType.expense, label: Text('Expense')),
                  ButtonSegment(value: TransactionType.income, label: Text('Income')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
            const SizedBox(height: 16),
            Text('Icon', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            IconPickerRow(selected: _icon, color: _color, onChanged: (i) => setState(() => _icon = i)),
            const SizedBox(height: 16),
            Text('Colour', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ColorPickerRow(selected: _color, onChanged: (c) => setState(() => _color = c)),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(key: const Key('saveCategory'), onPressed: _save, child: const Text('Save')),
            ),
          ],
        ),
      ),
    );
  }
}
