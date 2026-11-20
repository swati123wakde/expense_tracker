import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/category_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/models/goal.dart';
import '../../providers/bus_aware_notifier.dart';
import '../../providers/goals_provider.dart';
import '../common/amount_dialog.dart';
import '../common/common_widgets.dart';
import '../common/pickers.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<GoalsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Savings goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => GoalEditorSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Goal'),
      ),
      body: p.status == LoadStatus.error
          ? ErrorState(message: p.error ?? '', onRetry: p.load)
          : p.isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: ListSkeleton(count: 3))
              : p.goals.isEmpty
                  ? EmptyState(
                      icon: Icons.savings_outlined,
                      title: 'No savings goals yet',
                      message: 'Save towards a new laptop, a trip or an emergency fund.',
                      actionLabel: 'Create a goal',
                      onAction: () => GoalEditorSheet.show(context),
                    )
                  : ListView(
                      padding: Spacing.page,
                      children: [
                        AppCard(
                          color: Theme.of(context).colorScheme.secondaryContainer,
                          child: Row(
                            children: [
                              const Icon(Icons.savings, size: 32),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Saved ${Money.format(p.totalSavedMinor, p.baseCurrency)} '
                                  'of ${Money.format(p.totalTargetMinor, p.baseCurrency)}',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final g in p.goals)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _GoalCard(goal: g, currency: p.baseCurrency),
                          ),
                      ],
                    ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.currency});

  final GoalEntity goal;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = context.read<GoalsProvider>();
    final g = goal;
    final monthly = g.monthlyNeeded(DateTime.now());
    final colors = FinanceColors.of(context);
    return AppCard(
      onTap: () => GoalEditorSheet.show(context, existing: g),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryAvatar(icon: g.icon, color: g.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.name, style: Theme.of(context).textTheme.titleMedium),
                    if (g.targetDate != null)
                      Text(
                        'By ${DateFormat('d MMM y').format(g.targetDate!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (g.isComplete)
                Chip(
                  label: const Text('Reached'),
                  avatar: Icon(Icons.check_circle, color: colors.income, size: 18),
                )
              else
                Text('${(g.progress * 100).round()}%', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          BudgetProgressBar(progress: g.progress, percentUsed: 0),
          const SizedBox(height: 8),
          Text(
            'Target ${Money.format(g.targetMinor, currency)} • Saved ${Money.format(g.savedMinor, currency)}'
            '${g.isComplete ? '' : ' • ${Money.format(g.remainingMinor, currency)} to go'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (monthly != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Save ${Money.format(monthly, currency)} per month to reach it on time',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.remove),
                label: const Text('Withdraw'),
                onPressed: g.savedMinor == 0
                    ? null
                    : () async {
                        final v = await showAmountDialog(context, title: 'Withdraw from ${g.name}', currency: currency);
                        if (v != null) await p.contribute(g.id, -v);
                      },
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: const Text('Add money'),
                onPressed: () async {
                  final v = await showAmountDialog(context, title: 'Add to ${g.name}', currency: currency);
                  if (v != null) await p.contribute(g.id, v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GoalEditorSheet extends StatefulWidget {
  const GoalEditorSheet({super.key, this.existing});

  final GoalEntity? existing;

  static Future<void> show(BuildContext context, {GoalEntity? existing}) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => GoalEditorSheet(existing: existing),
      );

  @override
  State<GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<GoalEditorSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _target = TextEditingController(
    text: widget.existing == null ? '' : Money.toDecimalString(widget.existing!.targetMinor),
  );
  late final _saved = TextEditingController(
    text: widget.existing == null ? '' : Money.toDecimalString(widget.existing!.savedMinor),
  );
  late DateTime? _date = widget.existing?.targetDate;
  late String _icon = widget.existing?.icon ?? 'laptop';
  late int _color = widget.existing?.color ?? AppPalette.colors[6];

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final target = Money.parseToMinor(_target.text);
    final saved = Money.parseToMinor(_saved.text.isEmpty ? '0' : _saved.text);
    if (_name.text.trim().isEmpty || target == null || target <= 0 || saved == null || saved < 0) {
      showSnack(context, 'Enter a name, a target above zero and a valid saved amount', error: true);
      return;
    }
    final p = context.read<GoalsProvider>();
    final e = widget.existing;
    if (e == null) {
      await p.create(name: _name.text, targetMinor: target, savedMinor: saved, targetDate: _date, icon: _icon, color: _color);
    } else {
      await p.update(e.id, name: _name.text, targetMinor: target, savedMinor: saved, targetDate: _date, icon: _icon, color: _color);
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
            Text(e == null ? 'New goal' : 'Edit goal', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Goal name')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _target,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Target amount'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _saved,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Saved so far'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(_date == null ? 'Target date (optional)' : DateFormat('d MMM y').format(_date!)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now().add(const Duration(days: 90)),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 30)),
                );
                if (picked != null && mounted) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 16),
            IconPickerRow(
              selected: _icon,
              color: _color,
              keys: const ['laptop', 'vacation', 'car', 'house', 'savings', 'phone', 'education', 'gift', 'bike', 'diamond', 'star'],
              onChanged: (i) => setState(() => _icon = i),
            ),
            const SizedBox(height: 16),
            ColorPickerRow(selected: _color, onChanged: (c) => setState(() => _color = c)),
            const SizedBox(height: 24),
            Row(
              children: [
                if (e != null)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    onPressed: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Delete goal?',
                        message: '"${e.name}" will be removed.',
                        confirmLabel: 'Delete',
                        destructive: true,
                      );
                      if (!ok || !context.mounted) return;
                      await context.read<GoalsProvider>().delete(e.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
