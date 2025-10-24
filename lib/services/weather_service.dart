import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class WeatherService {
  // Barangay Cebulano, Carmen, Davao del Norte (approximate)
  static const double defaultLat = 7.3500;
  static const double defaultLon = 125.6720;

  // Simple in-memory cache to avoid hammering the API and triggering 429s
  static final Map<String, (_CachedWeather, DateTime)> _cache = {};
  static final Map<String, Future<WeatherSummary>> _inflight = {};
  static DateTime? _lastRequestTime;
  static const Duration _cacheTtl = Duration(minutes: 15);
  static const Duration _minRequestInterval = Duration(milliseconds: 1100);

  static Future<WeatherSummary> getAverageTemperature({
    required DateTime start,
    required DateTime end,
    double lat = defaultLat,
    double lon = defaultLon,
  }) async {
    final key = 'avg:$lat,$lon:${_fmt(start)}:${_fmt(end)}';

    // Return cached value if fresh
    final cached = _cache[key];
    if (cached != null) {
      final (_, storedAt) = cached;
      if (DateTime.now().difference(storedAt) < _cacheTtl) {
        return cached.$1.summary;
      }
    }

    // If the same request is already in-flight, await it
    final existing = _inflight[key];
    if (existing != null) return await existing;

    // Respect a minimum interval between network calls (free-tier rate limits)
    final now = DateTime.now();
    if (_lastRequestTime != null) {
      final since = now.difference(_lastRequestTime!);
      if (since < _minRequestInterval) {
        await Future.delayed(_minRequestInterval - since);
      }
    }

    final future = _fetchAverageTemperature(
      start: start,
      end: end,
      lat: lat,
      lon: lon,
    );
    _inflight[key] = future;
    try {
      final result = await future;
      _cache[key] = (_CachedWeather(summary: result), DateTime.now());
      _lastRequestTime = DateTime.now();
      return result;
    } finally {
      _inflight.remove(key);
    }
  }

  static Future<WeatherSummary> _fetchAverageTemperature({
    required DateTime start,
    required DateTime end,
    required double lat,
    required double lon,
  }) async {
    final startStr = _fmt(start);
    final endStr = _fmt(end);
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&daily=temperature_2m_max,temperature_2m_min&timezone=auto&start_date=$startStr&end_date=$endStr',
    );
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      return WeatherSummary.empty();
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final daily = data['daily'] as Map<String, dynamic>?;
    if (daily == null) return WeatherSummary.empty();
    final List tempsMax = daily['temperature_2m_max'] as List? ?? [];
    final List tempsMin = daily['temperature_2m_min'] as List? ?? [];
    if (tempsMax.isEmpty && tempsMin.isEmpty) return WeatherSummary.empty();

    final List<double> avgs = [];
    final len =
        tempsMax.length > tempsMin.length ? tempsMax.length : tempsMin.length;
    for (int i = 0; i < len; i++) {
      final dynamic maxRaw = i < tempsMax.length ? tempsMax[i] : null;
      final dynamic minRaw = i < tempsMin.length ? tempsMin[i] : null;
      final double maxV =
          maxRaw is num ? maxRaw.toDouble() : double.nan; // guard nulls
      final double minV =
          minRaw is num ? minRaw.toDouble() : double.nan; // guard nulls
      if (!maxV.isNaN && !minV.isNaN) {
        avgs.add((maxV + minV) / 2.0);
      } else if (!maxV.isNaN) {
        avgs.add(maxV);
      } else if (!minV.isNaN) {
        avgs.add(minV);
      }
    }
    if (avgs.isEmpty) return WeatherSummary.empty();

    final avg = avgs.reduce((a, b) => a + b) / avgs.length;
    final double? minAll = _safeMin(tempsMin);
    final double? maxAll = _safeMax(tempsMax);
    return WeatherSummary(averageC: avg, minC: minAll, maxC: maxAll);
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static double? _safeMin(List list) {
    if (list.isEmpty) return null;
    final doubles =
        list.where((e) => e is num).map((e) => (e as num).toDouble()).toList();
    doubles.sort();
    return doubles.first;
  }

  static double? _safeMax(List list) {
    if (list.isEmpty) return null;
    final doubles =
        list.where((e) => e is num).map((e) => (e as num).toDouble()).toList();
    doubles.sort();
    return doubles.last;
  }
}

class _CachedWeather {
  final WeatherSummary summary;
  _CachedWeather({required this.summary});
}

class WeatherSummary {
  final double? averageC;
  final double? minC;
  final double? maxC;

  WeatherSummary({
    required this.averageC,
    required this.minC,
    required this.maxC,
  });

  factory WeatherSummary.empty() =>
      WeatherSummary(averageC: null, minC: null, maxC: null);

  String toLabel() {
    if (averageC == null && minC == null && maxC == null) {
      return 'No weather data';
    }
    final parts = <String>[];
    if (averageC != null && averageC!.isFinite) {
      parts.add('Avg Temp ${averageC!.toStringAsFixed(1)}°C');
    }
    if (minC != null && maxC != null && minC!.isFinite && maxC!.isFinite) {
      // Use simple hyphen to avoid missing glyphs in PDF font
      parts.add(
        'Min/Max ${minC!.toStringAsFixed(0)}-${maxC!.toStringAsFixed(0)}°C',
      );
    }
    return parts.join(' | ');
  }
}
