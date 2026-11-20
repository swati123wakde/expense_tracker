import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/sync_provider.dart';
import '../../sync/sync_service.dart';

/// Compact sync indicator: "✓ Synced", "↻ Syncing...", "☁ 4 changes waiting",
/// "⚠ Sync failed" or "Offline • 3 changes will sync later". Tap to sync.
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final s = sync.state;
    final scheme = Theme.of(context).colorScheme;
    final finance = FinanceColors.of(context);

    final (IconData icon, Color color) = switch (s) {
      SyncState(phase: SyncPhase.disabled) => (Icons.phone_android, scheme.onSurfaceVariant),
      SyncState(online: false) => (Icons.cloud_off, scheme.onSurfaceVariant),
      SyncState(phase: SyncPhase.syncing) => (Icons.sync, scheme.primary),
      SyncState(phase: SyncPhase.failed) => (Icons.error_outline, finance.expense),
      SyncState(pendingCount: > 0) => (Icons.cloud_upload_outlined, finance.warning),
      _ => (Icons.cloud_done_outlined, finance.income),
    };

    return Tooltip(
      message: s.error ?? 'Tap to sync now',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: s.phase == SyncPhase.disabled ? null : () => sync.syncNow(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _stripGlyph(s.label),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The label already carries a glyph for text contexts; the chip uses icons.
  static String _stripGlyph(String label) => label.replaceFirst(RegExp(r'^[✓↻☁⚠]\s*'), '');
}
