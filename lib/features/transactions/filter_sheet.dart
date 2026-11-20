import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction_filter.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/categories_provider.dart';

enum DatePreset { all, today, thisWeek, thisMonth, lastMonth, custom }

/// Bottom sheet that edits a [TransactionFilter]. Every section combines
/// with every other (e.g. Expense + Food + This month + Cash).
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial});

  final TransactionFilter initial;

  static Future<TransactionFilter?> show(BuildContext context, TransactionFilter initial) =>
      showModalBottomSheet<TransactionFilter>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => FilterSheet(initial: initial),
      );

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late TransactionType? _type = widget.initial.type;
  late Set<String> _categories = {...widget.initial.categoryIds};
  late Set<String> _accounts = {...widget.initial.accountIds};
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;
  late bool _favorites = widget.initial.favoritesOnly;
  late final TextEditingController _min = TextEditingController(
    text: widget.initial.minAmountMinor == null ? '' : Money.toDecimalString(widget.initial.minAmountMinor!),
  );
  late final TextEditingController _max = TextEditingController(
    text: widget.initial.maxAmountMinor == null ? '' : Money.toDecimalString(widget.initial.maxAmountMinor!),
  );
  DatePreset _preset = DatePreset.all;

  @override
  void initState() {
    super.initState();
    if (_from != null || _to != null) _preset = _detectPreset();
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  DatePreset _detectPreset() {
    final now = DateTime.now();
    final range = DateRange(_from ?? DateTime(2000), _to ?? DateTime(2100));
    if (range == DateUtilsX.today(now)) return DatePreset.today;
    if (range == DateUtilsX.thisWeek(now)) return DatePreset.thisWeek;
    if (range == DateUtilsX.month(now)) return DatePreset.thisMonth;
    if (range == DateUtilsX.lastMonth(now)) return DatePreset.lastMonth;
    return DatePreset.custom;
  }

  Future<void> _selectPreset(DatePreset preset) async {
    final now = DateTime.now();
    DateRange? range;
    switch (preset) {
      case DatePreset.all:
        range = null;
      case DatePreset.today:
        range = DateUtilsX.today(now);
      case DatePreset.thisWeek:
        range = DateUtilsX.thisWeek(now);
      case DatePreset.thisMonth:
        range = DateUtilsX.month(now);
      case DatePreset.lastMonth:
        range = DateUtilsX.lastMonth(now);
      case DatePreset.custom:
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(now.year + 5),
          initialDateRange: _from != null && _to != null
              ? DateTimeRange(start: _from!, end: _to!.subtract(const Duration(days: 1)))
              : null,
        );
        if (picked == null) return;
        range = DateRange(
          DateUtilsX.startOfDay(picked.start),
          DateUtilsX.startOfDay(picked.end).add(const Duration(days: 1)),
        );
    }
    if (!mounted) return;
    setState(() {
      _preset = preset;
      _from = range?.start;
      _to = range?.end;
    });
  }

  void _apply() {
    final min = Money.parseToMinor(_min.text);
    final max = Money.parseToMinor(_max.text);
    Navigator.pop(
      context,
      TransactionFilter(
        type: _type,
        categoryIds: _categories,
        accountIds: _accounts,
        from: _from,
        to: _to,
        minAmountMinor: min,
        maxAmountMinor: max,
        favoritesOnly: _favorites,
        query: widget.initial.query,
      ),
    );
  }

  void _reset() => setState(() {
        _type = null;
        _categories = {};
        _accounts = {};
        _from = null;
        _to = null;
        _favorites = false;
        _preset = DatePreset.all;
        _min.clear();
        _max.clear();
      });

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<CategoriesProvider>().all.where((c) => _type == null || c.type == _type);
    final accounts = context.watch<AccountsProvider>().accounts;
    final title = Theme.of(context).textTheme.titleSmall;
    final fmt = DateFormat('d MMM y');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text('Type', style: title),
                const SizedBox(height: 8),
                SegmentedButton<TransactionType?>(
                  segments: const [
                    ButtonSegment(value: null, label: Text('All')),
                    ButtonSegment(value: TransactionType.expense, label: Text('Expense')),
                    ButtonSegment(value: TransactionType.income, label: Text('Income')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: 20),
                Text('Date', style: title),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in DatePreset.values)
                      ChoiceChip(
                        key: Key('preset_${p.name}'),
                        label: Text(_presetLabel(p)),
                        selected: _preset == p,
                        onSelected: (_) => _selectPreset(p),
                      ),
                  ],
                ),
                if (_from != null && _to != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${fmt.format(_from!)} – ${fmt.format(_to!.subtract(const Duration(days: 1)))}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 20),
                Text('Category', style: title),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in categories)
                      FilterChip(
                        key: Key('filter_cat_${c.id}'),
                        label: Text(c.name),
                        selected: _categories.contains(c.id),
                        onSelected: (v) => setState(() => v ? _categories.add(c.id) : _categories.remove(c.id)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Account', style: title),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in accounts)
                      FilterChip(
                        label: Text(a.name),
                        selected: _accounts.contains(a.id),
                        onSelected: (v) => setState(() => v ? _accounts.add(a.id) : _accounts.remove(a.id)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Amount', style: title),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _min,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Min'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _max,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Max'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Favorites only'),
                  value: _favorites,
                  onChanged: (v) => setState(() => _favorites = v),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                key: const Key('applyFilters'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _apply,
                child: const Text('Apply filters'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _presetLabel(DatePreset p) => switch (p) {
        DatePreset.all => 'All time',
        DatePreset.today => 'Today',
        DatePreset.thisWeek => 'This week',
        DatePreset.thisMonth => 'This month',
        DatePreset.lastMonth => 'Last month',
        DatePreset.custom => 'Custom range',
      };
}
