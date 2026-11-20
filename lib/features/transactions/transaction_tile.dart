import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction.dart';
import '../common/common_widgets.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.view, this.onTap, this.dense = false});

  final TransactionView view;
  final VoidCallback? onTap;
  final bool dense;

  static final DateFormat _date = DateFormat('d MMM y');
  static final DateFormat _time = DateFormat.jm();

  @override
  Widget build(BuildContext context) {
    final t = view.transaction;
    final scheme = Theme.of(context).colorScheme;
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final title = t.note.isNotEmpty ? t.note : view.categoryName;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: Spacing.md, vertical: dense ? 8 : 12),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CategoryAvatar(icon: view.categoryIcon, color: view.categoryColor),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: _TypeBadge(type: t.type),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (t.isFavorite) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.star_rounded, size: 16, color: FinanceColors.of(context).warning),
                      ],
                      if (t.recurringRuleId != null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.repeat, size: 14, color: scheme.onSurfaceVariant),
                      ],
                      if (t.attachmentPath != null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.attach_file, size: 14, color: scheme.onSurfaceVariant),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.note.isNotEmpty
                        ? '${view.categoryName} • ${view.accountName}'
                        : view.accountName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountText(amountMinor: t.amountMinor, currency: view.currency, type: t.type),
                const SizedBox(height: 2),
                Text(
                  dense ? _date.format(t.occurredAt) : '${_date.format(t.occurredAt)} • ${_time.format(t.occurredAt)}',
                  style: subtitleStyle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final TransactionType type;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final income = type == TransactionType.income;
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
      ),
      child: Icon(
        income ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
        size: 13,
        color: income ? colors.income : colors.expense,
        semanticLabel: income ? 'Income' : 'Expense',
      ),
    );
  }
}
