import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/category_icons.dart';
import '../../core/constants/defaults.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/models/account.dart';
import '../../data/models/enums.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/bus_aware_notifier.dart';
import '../common/common_widgets.dart';
import '../common/pickers.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AccountsProvider>();
    final active = p.balances.where((b) => !b.account.archived).toList();
    final archived = p.balances.where((b) => b.account.archived).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts & wallets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AccountEditorSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Account'),
      ),
      body: p.status == LoadStatus.error
          ? ErrorState(message: p.error ?? '', onRetry: p.load)
          : p.isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: ListSkeleton(count: 3))
              : ListView(
                  padding: Spacing.page,
                  children: [
                    AppCard(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Combined balance'),
                          const SizedBox(height: 4),
                          Text(
                            Money.format(p.summary.balanceMinor, p.baseCurrency),
                            key: const Key('combinedBalance'),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          if (p.balances.any((b) => b.account.currency != p.baseCurrency))
                            Text(
                              'Converted to ${p.baseCurrency} using '
                              '${p.converter.fetchedAt == null ? 'approximate' : 'cached'} exchange rates',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    const SectionHeader(title: 'Accounts'),
                    if (active.isEmpty)
                      const EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'No accounts'),
                    for (final b in active) _AccountTile(balance: b, converted: p.summary.convertedBalances[b.account.id]),
                    if (archived.isNotEmpty) ...[
                      const SectionHeader(title: 'Archived'),
                      for (final b in archived) _AccountTile(balance: b, converted: null),
                    ],
                  ],
                ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.balance, required this.converted});

  final AccountBalance balance;
  final int? converted;

  @override
  Widget build(BuildContext context) {
    final a = balance.account;
    final base = context.read<AccountsProvider>().baseCurrency;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () => AccountEditorSheet.show(context, existing: a),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CategoryAvatar(icon: a.icon, color: a.color),
          title: Text(a.name),
          subtitle: Text('${a.type.label} • ${a.currency}${a.archived ? ' • Archived' : ''}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Money.format(balance.balanceMinor, a.currency), style: Theme.of(context).textTheme.titleMedium),
              if (a.currency != base && converted != null)
                Text('≈ ${Money.format(converted!, base)}', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountEditorSheet extends StatefulWidget {
  const AccountEditorSheet({super.key, this.existing});

  final AccountEntity? existing;

  static Future<void> show(BuildContext context, {AccountEntity? existing}) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AccountEditorSheet(existing: existing),
      );

  @override
  State<AccountEditorSheet> createState() => _AccountEditorSheetState();
}

class _AccountEditorSheetState extends State<AccountEditorSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _opening = TextEditingController();
  late AccountType _type = widget.existing?.type ?? AccountType.bank;
  late String _currency = widget.existing?.currency ?? context.read<AccountsProvider>().baseCurrency;
  late String _icon = widget.existing?.icon ?? 'bank';
  late int _color = widget.existing?.color ?? AppPalette.colors[1];
  bool _saving = false;
  int _txCount = 0;

  @override
  void initState() {
    super.initState();
    final id = widget.existing?.id;
    if (id != null) {
      context.read<AccountsProvider>().transactionCount(id).then((c) {
        if (mounted) setState(() => _txCount = c);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  static const _typeIcons = {
    AccountType.cash: 'cash',
    AccountType.bank: 'bank',
    AccountType.creditCard: 'credit_card',
    AccountType.wallet: 'wallet',
    AccountType.savings: 'savings',
  };

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Enter an account name', error: true);
      return;
    }
    final p = context.read<AccountsProvider>();
    setState(() => _saving = true);
    try {
      final e = widget.existing;
      if (e == null) {
        await p.create(
          name: _name.text,
          type: _type,
          currency: _currency,
          icon: _icon,
          color: _color,
          openingBalanceMinor: Money.parseToMinor(_opening.text) ?? 0,
        );
      } else {
        await p.update(e.copyWith(name: _name.text, type: _type, currency: _currency, icon: _icon, color: _color));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save account', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archiveOrDelete() async {
    final e = widget.existing!;
    final p = context.read<AccountsProvider>();
    if (_txCount > 0 || e.archived) {
      await p.setArchived(e.id, !e.archived);
      if (mounted) Navigator.pop(context);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Delete ${e.name}?',
      message: 'This account has no transactions and will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await p.delete(e.id);
      if (mounted) Navigator.pop(context);
    } on StateError catch (err) {
      if (mounted) showSnack(context, err.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    // Changing currency would re-denominate existing transactions.
    final currencyLocked = e != null && _txCount > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e == null ? 'New account' : 'Edit account', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AccountType>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final t in AccountType.values) DropdownMenuItem(value: t, child: Text(t.label))],
              onChanged: (t) => setState(() {
                _type = t ?? _type;
                _icon = _typeIcons[_type] ?? _icon;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: Defaults.currencies.contains(_currency) ? _currency : null,
              decoration: InputDecoration(
                labelText: 'Currency',
                helperText: currencyLocked ? 'Currency is locked once an account has transactions' : null,
              ),
              items: [for (final c in Defaults.currencies) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: currencyLocked ? null : (c) => setState(() => _currency = c ?? _currency),
            ),
            if (e == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _opening,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Opening balance (optional)', prefixText: '${Money.symbol(_currency)} '),
              ),
            ],
            const SizedBox(height: 16),
            Text('Icon', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            IconPickerRow(
              selected: _icon,
              color: _color,
              keys: const ['cash', 'bank', 'credit_card', 'wallet', 'savings', 'money', 'diamond', 'business'],
              onChanged: (i) => setState(() => _icon = i),
            ),
            const SizedBox(height: 16),
            Text('Colour', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ColorPickerRow(selected: _color, onChanged: (c) => setState(() => _color = c)),
            const SizedBox(height: 24),
            Row(
              children: [
                if (e != null)
                  TextButton.icon(
                    onPressed: _archiveOrDelete,
                    icon: Icon(e.archived ? Icons.unarchive_outlined : (_txCount > 0 ? Icons.archive_outlined : Icons.delete_outline)),
                    label: Text(e.archived ? 'Unarchive' : (_txCount > 0 ? 'Archive' : 'Delete')),
                  ),
                const Spacer(),
                FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
