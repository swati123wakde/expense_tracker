import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common/sqlite_api.dart';

import '../constants/defaults.dart';
import '../finance/currency_converter.dart';
import 'data_change_bus.dart';

/// Source of live rates (units per USD). Swappable for tests.
abstract class RateSource {
  Future<Map<String, double>> fetchRatesPerUsd();
}

class OpenErApiRateSource implements RateSource {
  OpenErApiRateSource([http.Client? client]) : _client = client ?? http.Client();

  final http.Client _client;
  static final Uri _uri = Uri.parse('https://open.er-api.com/v6/latest/USD');

  @override
  Future<Map<String, double>> fetchRatesPerUsd() async {
    final res = await _client.get(_uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}', _uri);
    final body = jsonDecode(res.body);
    if (body is! Map || body['rates'] is! Map) throw const FormatException('Unexpected rate payload');
    final rates = <String, double>{};
    (body['rates'] as Map).forEach((k, v) {
      if (k is String && v is num && v > 0) rates[k] = v.toDouble();
    });
    return rates;
  }
}

/// Caches exchange rates in the local DB. Online: refreshed at most every
/// [maxAge]. Offline: the last known rates are used (or bundled fallbacks
/// before the first successful fetch).
class ExchangeRateService {
  ExchangeRateService(this._db, this._source, this._bus, {this.maxAge = const Duration(hours: 12)});

  final Database _db;
  final RateSource _source;
  final DataChangeBus _bus;
  final Duration maxAge;

  Future<CurrencyConverter> converter(String baseCurrency) async {
    final rows = await _db.query(Tables.exchangeRates);
    if (rows.isEmpty) {
      return CurrencyConverter(baseCurrency: baseCurrency, ratesPerUsd: Defaults.fallbackRatesPerUsd);
    }
    var fetchedAt = 0;
    final rates = <String, double>{};
    for (final r in rows) {
      rates[r['currency'] as String] = (r['rate_per_usd'] as num).toDouble();
      final f = (r['fetched_at'] as num).toInt();
      if (f > fetchedAt) fetchedAt = f;
    }
    return CurrencyConverter(
      baseCurrency: baseCurrency,
      ratesPerUsd: {...Defaults.fallbackRatesPerUsd, ...rates},
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt),
    );
  }

  Future<DateTime?> lastFetchedAt() async {
    final r = await _db.rawQuery('SELECT MAX(fetched_at) AS f FROM ${Tables.exchangeRates}');
    final v = r.first['f'];
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
  }

  /// Refreshes cached rates when stale. Never throws: failures keep the cache.
  Future<bool> refreshIfStale({bool force = false}) async {
    try {
      final last = await lastFetchedAt();
      if (!force && last != null && DateTime.now().difference(last) < maxAge) return false;
      final rates = await _source.fetchRatesPerUsd();
      if (rates.isEmpty) return false;
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = _db.batch();
      rates.forEach((currency, rate) {
        batch.insert(
          Tables.exchangeRates,
          {'currency': currency, 'rate_per_usd': rate, 'fetched_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await batch.commit(noResult: true);
      _bus.emit({Tables.exchangeRates}, origin: ChangeOrigin.sync);
      return true;
    } catch (e) {
      debugPrint('Exchange rate refresh failed: $e');
      return false;
    }
  }
}
