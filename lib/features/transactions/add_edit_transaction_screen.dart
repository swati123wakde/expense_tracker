import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/transactions_provider.dart';
import '../common/common_widgets.dart';

/// Create a new transaction, or edit [existing].
class AddEditTransactionScreen extends StatefulWidget {
  const AddEditTransactionScreen({super.key, this.existing, this.initialType = TransactionType.expense});

  final TransactionEntity? existing;
  final TransactionType initialType;

  static Future<bool?> open(BuildContext context, {TransactionEntity? existing}) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AddEditTransactionScreen(existing: existing),
        ),
      );

  @override
  State<AddEditTransactionScreen> createState() => _AddEditTransactionScreenState();
}

class _AddEditTransactionScreenState extends State<AddEditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late TransactionType _type;
  String? _categoryId;
  String? _accountId;
  late DateTime _date;
  late TimeOfDay _time;
  String? _attachment;
  bool _recurring = false;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  bool _saving = false;
  String? _categoryError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? widget.initialType;
    _amount = TextEditingController(text: e == null ? '' : Money.toDecimalString(e.amountMinor));
    _note = TextEditingController(text: e?.note ?? '');
    _categoryId = e?.categoryId;
    _accountId = e?.accountId;
    final when = e?.occurredAt ?? DateTime.now();
    _date = DateTime(when.year, when.month, when.day);
    _time = TimeOfDay.fromDateTime(when);
    _attachment = e?.attachmentPath;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime get _occurredAt => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _save() async {
    final categories = context.read<CategoriesProvider>();
    final accounts = context.read<AccountsProvider>();
    setState(() => _categoryError = _categoryId == null ? 'Choose a category' : null);
    if (!(_formKey.currentState?.validate() ?? false) || _categoryId == null) return;

    final accountId = _accountId ?? (accounts.active.isNotEmpty ? accounts.active.first.id : null);
    if (accountId == null) {
      showSnack(context, 'Create an account first', error: true);
      return;
    }
    if (categories.byId[_categoryId]?.type != _type) {
      setState(() => _categoryError = 'Choose a ${_type.label.toLowerCase()} category');
      return;
    }

    final draft = TransactionDraft(
      type: _type,
      amountMinor: Money.parseToMinor(_amount.text)!,
      categoryId: _categoryId!,
      accountId: accountId,
      occurredAt: _occurredAt,
      note: _note.text,
      attachmentPath: _attachment,
      recurrence: !_isEdit && _recurring ? _frequency : null,
    );

    setState(() => _saving = true);
    final provider = context.read<TransactionsProvider>();
    try {
      if (_isEdit) {
        await provider.update(widget.existing!.id, draft);
      } else {
        await provider.add(draft);
      }
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      if (mounted) showSnack(context, '${e.message}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save the transaction', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _pickAttachment() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600);
      if (file == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final target = Directory(p.join(dir.path, 'attachments'));
      if (!target.existsSync()) target.createSync(recursive: true);
      final saved = await File(file.path).copy(
        p.join(target.path, '${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}'),
      );
      if (mounted) setState(() => _attachment = saved.path);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not attach image', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<CategoriesProvider>();
    final accounts = context.watch<AccountsProvider>();
    final colors = FinanceColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final options = categories.active(_type);
    final activeAccounts = accounts.active;
    final selectedAccount = accounts.byId(_accountId ?? '') ??
        (activeAccounts.isNotEmpty ? activeAccounts.first : null);
    final currency = selectedAccount?.currency ?? accounts.baseCurrency;
    final accent = _type == TransactionType.income ? colors.income : colors.expense;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit transaction' : 'Add transaction'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(value: TransactionType.expense, label: Text('Expense'), icon: Icon(Icons.arrow_upward)),
                ButtonSegment(value: TransactionType.income, label: Text('Income'), icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                if (categories.byId[_categoryId]?.type != _type) _categoryId = null;
              }),
            ),
            const SizedBox(height: Spacing.lg),
            TextFormField(
              key: const Key('amountField'),
              controller: _amount,
              autofocus: !_isEdit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: accent),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '${Money.symbol(currency)} ',
                prefixStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(color: accent),
              ),
              validator: (v) {
                final minor = Money.parseToMinor(v ?? '');
                if (minor == null) return 'Enter a valid amount';
                if (minor <= 0) return 'Amount must be greater than zero';
                return null;
              },
            ),
            const SizedBox(height: Spacing.lg),
            Text('Category', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            _CategoryGrid(
              categories: options,
              selectedId: _categoryId,
              onSelected: (id) => setState(() {
                _categoryId = id;
                _categoryError = null;
              }),
            ),
            if (_categoryError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_categoryError!, style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
            const SizedBox(height: Spacing.lg),
            Text('Account', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in activeAccounts)
                  ChoiceChip(
                    label: Text(a.currency == accounts.baseCurrency ? a.name : '${a.name} (${a.currency})'),
                    selected: selectedAccount?.id == a.id,
                    onSelected: (_) => setState(() => _accountId = a.id),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            TextFormField(
              key: const Key('noteField'),
              controller: _note,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note', prefixIcon: Icon(Icons.notes)),
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(DateFormat('EEE, d MMM y').format(_date)),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_time.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file),
              title: Text(_attachment == null ? 'Add receipt (optional)' : 'Receipt attached'),
              subtitle: _attachment == null ? null : Text(p.basename(_attachment!), maxLines: 1),
              trailing: _attachment == null
                  ? const Icon(Icons.add_photo_alternate_outlined)
                  : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _attachment = null)),
              onTap: _pickAttachment,
            ),
            if (_attachment != null && File(_attachment!).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(_attachment!), height: 160, fit: BoxFit.cover),
              ),
            if (!_isEdit) ...[
              SwitchListTile(
                key: const Key('recurringSwitch'),
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.repeat),
                title: const Text('Recurring'),
                subtitle: const Text('Automatically add this transaction on schedule'),
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _recurring
                    ? Wrap(
                        spacing: 8,
                        children: [
                          for (final f in RecurrenceFrequency.values)
                            ChoiceChip(
                              label: Text(f.label),
                              selected: _frequency == f,
                              onSelected: (_) => setState(() => _frequency = f),
                            ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const Key('saveTransaction'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_isEdit ? 'Save changes' : 'Save'),
          ),
        ),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories, required this.selectedId, required this.onSelected});

  final List<CategoryEntity> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final raw = (constraints.maxWidth / 84).floor();
        final columns = raw < 3 ? 3 : (raw > 8 ? 8 : raw);
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in categories)
              SizedBox(
                width: width,
                child: InkWell(
                  key: Key('category_${c.id}'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onSelected(c.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selectedId == c.id ? Color(c.color) : scheme.outlineVariant,
                        width: selectedId == c.id ? 2 : 1,
                      ),
                      color: selectedId == c.id ? Color(c.color).withValues(alpha: 0.08) : null,
                    ),
                    child: Column(
                      children: [
                        CategoryAvatar(icon: c.icon, color: c.color, size: 36),
                        const SizedBox(height: 6),
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
