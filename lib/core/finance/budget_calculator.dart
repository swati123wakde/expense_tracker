/// Progress of one budget (overall monthly or per category) for a month.
class BudgetStatus {
  const BudgetStatus({
    required this.budgetId,
    required this.limitMinor,
    required this.spentMinor,
    this.categoryId,
  });

  static const List<int> warningThresholds = [50, 75, 90, 100];

  final String budgetId;
  final String? categoryId;
  final int limitMinor;
  final int spentMinor;

  bool get hasLimit => limitMinor > 0;

  int get remainingMinor => limitMinor - spentMinor;

  /// 0..∞ percentage (may exceed 100).
  double get percentUsed => limitMinor <= 0 ? 0 : spentMinor * 100 / limitMinor;

  /// Fraction for progress bars, clamped to 0..1.
  double get progress => (percentUsed / 100).clamp(0.0, 1.0).toDouble();

  bool get isExceeded => hasLimit && spentMinor > limitMinor;

  int get exceededByMinor => isExceeded ? spentMinor - limitMinor : 0;

  /// Highest warning threshold reached (50/75/90/100) or null.
  int? get reachedThreshold {
    if (!hasLimit) return null;
    int? reached;
    for (final t in warningThresholds) {
      if (percentUsed >= t) reached = t;
    }
    return reached;
  }
}

enum BudgetSeverity { ok, info, warning, critical, exceeded }

class BudgetCalculator {
  BudgetCalculator._();

  static BudgetStatus status({
    required String budgetId,
    required int limitMinor,
    required int spentMinor,
    String? categoryId,
  }) =>
      BudgetStatus(
        budgetId: budgetId,
        categoryId: categoryId,
        limitMinor: limitMinor,
        spentMinor: spentMinor,
      );

  static BudgetSeverity severity(BudgetStatus s) {
    if (s.isExceeded) return BudgetSeverity.exceeded;
    switch (s.reachedThreshold) {
      case 100:
      case 90:
        return BudgetSeverity.critical;
      case 75:
        return BudgetSeverity.warning;
      case 50:
        return BudgetSeverity.info;
      default:
        return BudgetSeverity.ok;
    }
  }

  /// User-facing warning, e.g. "You have used 90% of your July budget." or
  /// "Budget exceeded by $125.". Returns null below 50%.
  static String? warningMessage(
    BudgetStatus s, {
    required String monthName,
    required String Function(int minor) format,
    String? categoryName,
  }) {
    if (!s.hasLimit) return null;
    final label = categoryName == null ? '$monthName budget' : '$categoryName budget for $monthName';
    if (s.isExceeded) {
      final prefix = categoryName == null ? 'Budget' : '$categoryName budget';
      return '$prefix exceeded by ${format(s.exceededByMinor)}.';
    }
    final t = s.reachedThreshold;
    if (t == null) return null;
    if (t == 100) return 'You have used 100% of your $label.';
    return 'You have used $t% of your $label.';
  }
}
