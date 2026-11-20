import 'package:intl/intl.dart';

/// All monetary values are stored as integer minor units (e.g. cents) to avoid
/// floating point drift. Two decimal places are assumed for every currency.
class Money {
  Money._();

  static const int scale = 100;

  static final Map<String, NumberFormat> _formatCache = {};
  static final Map<String, NumberFormat> _compactCache = {};

  static NumberFormat _formatter(String currency) => _formatCache.putIfAbsent(
        currency,
        () => NumberFormat.simpleCurrency(name: currency, decimalDigits: 2),
      );

  static String format(int minor, String currency, {bool signed = false}) {
    final value = minor / scale;
    final text = _formatter(currency).format(value.abs());
    if (minor < 0) return '-$text';
    if (signed && minor > 0) return '+$text';
    return text;
  }

  /// Short form for chart axes and dense UI, e.g. $1.2K.
  static String compact(int minor, String currency) {
    final f = _compactCache.putIfAbsent(
      currency,
      () => NumberFormat.compactSimpleCurrency(name: currency),
    );
    return f.format(minor / scale);
  }

  static String symbol(String currency) => _formatter(currency).currencySymbol;

  /// Plain decimal representation used in CSV/JSON exports: 1250 -> "12.5".
  static String toDecimalString(int minor) {
    final negative = minor < 0;
    final abs = minor.abs();
    final whole = abs ~/ scale;
    final frac = abs % scale;
    final fracStr = frac == 0
        ? ''
        : '.${frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0+$'), '')}';
    return '${negative ? '-' : ''}$whole$fracStr';
  }

  /// Parses user input like "1,234.50", "12.5" or "12" into minor units.
  /// Returns null for invalid input or more than 2 decimal places.
  static int? parseToMinor(String input) {
    final cleaned = input.trim().replaceAll(',', '').replaceAll(' ', '');
    if (cleaned.isEmpty) return null;
    final match = RegExp(r'^(-)?(\d+)(?:\.(\d{0,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final negative = match.group(1) != null;
    final whole = int.parse(match.group(2)!);
    final fracRaw = match.group(3) ?? '';
    final frac = fracRaw.isEmpty ? 0 : int.parse(fracRaw.padRight(2, '0'));
    final value = whole * scale + frac;
    return negative ? -value : value;
  }
}
