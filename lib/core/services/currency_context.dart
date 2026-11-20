import 'dart:async';

import '../../data/models/app_settings.dart';
import '../../data/repositories/settings_repository.dart';
import '../finance/currency_converter.dart';
import 'data_change_bus.dart';
import 'exchange_rate_service.dart';

/// Shared, cached access to the base currency and a converter built from the
/// locally cached exchange rates. Invalidated when settings or rates change.
class CurrencyContext {
  CurrencyContext(this._settings, this._rates, DataChangeBus bus) {
    _sub = bus.stream.listen((c) {
      if (c.touches(Tables.settings) || c.touches(Tables.exchangeRates)) _cached = null;
    });
  }

  final SettingsRepository _settings;
  final ExchangeRateService _rates;
  late final StreamSubscription<DataChange> _sub;
  Future<CurrencyConverter>? _cached;

  Future<CurrencyConverter> converter() => _cached ??= _build();

  Future<String> baseCurrency() async => (await converter()).baseCurrency;

  Future<CurrencyConverter> _build() async {
    final base = await _settings.get(SettingsKeys.baseCurrency) ?? 'USD';
    return _rates.converter(base);
  }

  void invalidate() => _cached = null;

  Future<void> dispose() => _sub.cancel();
}
