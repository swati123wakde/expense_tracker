/// Converts minor-unit amounts between currencies using rates expressed as
/// "units of currency per 1 USD". Rates are cached locally so conversion keeps
/// working offline with the last known values.
class CurrencyConverter {
  CurrencyConverter({
    required this.baseCurrency,
    Map<String, double> ratesPerUsd = const {},
    this.fetchedAt,
  }) : _rates = {'USD': 1.0, ...ratesPerUsd};

  /// Converter that only knows the base currency (everything 1:1).
  factory CurrencyConverter.identity(String baseCurrency) =>
      CurrencyConverter(baseCurrency: baseCurrency, ratesPerUsd: {baseCurrency: 1.0});

  final String baseCurrency;
  final DateTime? fetchedAt;
  final Map<String, double> _rates;

  Map<String, double> get rates => Map.unmodifiable(_rates);

  bool canConvert(String currency) =>
      currency == baseCurrency ||
      (_rates.containsKey(currency) && _rates.containsKey(baseCurrency));

  /// Converts [minor] from [from] into [to] (defaults to the base currency).
  /// Unknown currencies are passed through unchanged (1:1) rather than
  /// throwing, and [canConvert] lets the UI flag the approximation.
  int convert(int minor, String from, {String? to}) {
    final target = to ?? baseCurrency;
    if (from == target || minor == 0) return minor;
    final fromRate = _rates[from];
    final toRate = _rates[target];
    if (fromRate == null || toRate == null || fromRate == 0) return minor;
    return (minor / fromRate * toRate).round();
  }
}
