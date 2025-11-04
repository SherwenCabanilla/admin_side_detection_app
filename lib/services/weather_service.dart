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
    final now = DateTime.now();
    final cutoffDate = now.subtract(const Duration(days: 7));

    // Check if range spans both historical and recent periods
    final bool startIsHistorical = start.isBefore(cutoffDate);
    final bool endIsRecent = !end.isBefore(cutoffDate);

    // If range spans both periods, split and merge
    if (startIsHistorical && endIsRecent) {
      // Split the range: historical part and recent part
      final historicalEnd = cutoffDate.subtract(const Duration(days: 1));
      final recentStart = cutoffDate;

      // Fetch from both endpoints
      final historicalFuture = _fetchAverageTemperature(
        start: start,
        end: historicalEnd,
        lat: lat,
        lon: lon,
        endpoint: 'archive',
      );

      // Add delay between requests
      if (_lastRequestTime != null) {
        final since = DateTime.now().difference(_lastRequestTime!);
        if (since < _minRequestInterval) {
          await Future.delayed(_minRequestInterval - since);
        }
      }

      final recentFuture = _fetchAverageTemperature(
        start: recentStart,
        end: end,
        lat: lat,
        lon: lon,
        endpoint: 'forecast',
      );

      // Wait for both requests
      final historical = await historicalFuture;
      _lastRequestTime = DateTime.now();
      final recent = await recentFuture;
      _lastRequestTime = DateTime.now();

      // Merge the results
      return _mergeWeatherSummaries(historical, recent);
    }

    // Single endpoint case - use existing logic
    final endpoint = _determineEndpoint(start, end);
    final key = '$endpoint:avg:$lat,$lon:${_fmt(start)}:${_fmt(end)}';

    // For archive requests, don't use cache if it's empty (might be old failed requests)
    // Return cached value if fresh and not empty
    final cached = _cache[key];
    if (cached != null) {
      final (weatherData, storedAt) = cached;
      if (DateTime.now().difference(storedAt) < _cacheTtl) {
        // Only return cached if it has valid data (not empty)
        if (weatherData.summary.averageC != null ||
            weatherData.summary.minC != null ||
            weatherData.summary.maxC != null) {
          return weatherData.summary;
        }
        // If cached result is empty and it's an archive request, try fetching again
        // (might have been a failed request before the archive endpoint was added)
        if (endpoint == 'archive') {
          // Clear the empty cache and fetch fresh
          _cache.remove(key);
        } else {
          return weatherData.summary;
        }
      }
    }

    // If the same request is already in-flight, await it
    final existing = _inflight[key];
    if (existing != null) return await existing;

    // Respect a minimum interval between network calls (free-tier rate limits)
    if (_lastRequestTime != null) {
      final since = DateTime.now().difference(_lastRequestTime!);
      if (since < _minRequestInterval) {
        await Future.delayed(_minRequestInterval - since);
      }
    }

    final future = _fetchAverageTemperature(
      start: start,
      end: end,
      lat: lat,
      lon: lon,
      endpoint: endpoint,
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

  /// Determines which API endpoint to use based on the date range.
  /// Returns 'archive' for historical data (more than 7 days ago) or 'forecast' for recent data.
  static String _determineEndpoint(DateTime start, DateTime end) {
    final now = DateTime.now();
    final cutoffDate = now.subtract(const Duration(days: 7));

    // If end date is more than 7 days ago, use archive endpoint for historical data
    if (end.isBefore(cutoffDate)) {
      return 'archive';
    }

    // For recent dates (within last 7 days), use forecast endpoint
    return 'forecast';
  }

  static Future<WeatherSummary> _fetchAverageTemperature({
    required DateTime start,
    required DateTime end,
    required double lat,
    required double lon,
    required String endpoint,
  }) async {
    final startStr = _fmt(start);
    final endStr = _fmt(end);

    // Use archive endpoint for historical data, forecast for recent data
    // IMPORTANT: Archive API uses a DIFFERENT base URL: archive-api.open-meteo.com
    final String baseUrl;
    final String endpointPath;

    if (endpoint == 'archive') {
      // Archive API uses different base domain
      baseUrl = 'https://archive-api.open-meteo.com';
      endpointPath = 'v1/archive';
    } else {
      // Forecast API uses standard base domain
      baseUrl = 'https://api.open-meteo.com';
      endpointPath = 'v1/forecast';
    }

    // Build the API URL with correct base URL for each endpoint type
    final uri = Uri.parse(
      '$baseUrl/$endpointPath?latitude=$lat&longitude=$lon&daily=temperature_2m_max,temperature_2m_min&timezone=auto&start_date=$startStr&end_date=$endStr',
    );

    try {
      final resp = await http.get(uri);

      if (resp.statusCode != 200) {
        // If archive fails, try forecast as fallback (for edge cases)
        if (endpoint == 'archive') {
          // Try forecast endpoint as fallback (though it won't work for old dates)
          final fallbackUri = Uri.parse(
            'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&daily=temperature_2m_max,temperature_2m_min&timezone=auto&start_date=$startStr&end_date=$endStr',
          );
          final fallbackResp = await http.get(fallbackUri);
          if (fallbackResp.statusCode == 200) {
            final fallbackData =
                json.decode(fallbackResp.body) as Map<String, dynamic>;
            final fallbackDaily =
                fallbackData['daily'] as Map<String, dynamic>?;
            if (fallbackDaily != null) {
              final List tempsMax =
                  fallbackDaily['temperature_2m_max'] as List? ?? [];
              final List tempsMin =
                  fallbackDaily['temperature_2m_min'] as List? ?? [];
              if (tempsMax.isNotEmpty || tempsMin.isNotEmpty) {
                return _processTemperatureData(tempsMax, tempsMin);
              }
            }
          }
        }
        return WeatherSummary.empty();
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final daily = data['daily'] as Map<String, dynamic>?;
      if (daily == null) return WeatherSummary.empty();

      final List tempsMax = daily['temperature_2m_max'] as List? ?? [];
      final List tempsMin = daily['temperature_2m_min'] as List? ?? [];

      // Check if we have any valid data (arrays might contain null values)
      if (tempsMax.isEmpty && tempsMin.isEmpty) return WeatherSummary.empty();

      return _processTemperatureData(tempsMax, tempsMin);
    } catch (e) {
      // If archive fails, try forecast as fallback (though unlikely to work for historical dates)
      if (endpoint == 'archive') {
        try {
          final fallbackUri = Uri.parse(
            'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&daily=temperature_2m_max,temperature_2m_min&timezone=auto&start_date=$startStr&end_date=$endStr',
          );
          final fallbackResp = await http.get(fallbackUri);
          if (fallbackResp.statusCode == 200) {
            final fallbackData =
                json.decode(fallbackResp.body) as Map<String, dynamic>;
            final fallbackDaily =
                fallbackData['daily'] as Map<String, dynamic>?;
            if (fallbackDaily != null) {
              final List tempsMax =
                  fallbackDaily['temperature_2m_max'] as List? ?? [];
              final List tempsMin =
                  fallbackDaily['temperature_2m_min'] as List? ?? [];
              if (tempsMax.isNotEmpty || tempsMin.isNotEmpty) {
                return _processTemperatureData(tempsMax, tempsMin);
              }
            }
          }
        } catch (_) {
          // Ignore fallback errors
        }
      }
      return WeatherSummary.empty();
    }
  }

  static WeatherSummary _processTemperatureData(List tempsMax, List tempsMin) {
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

  /// Clears the weather cache. Useful when you want to force fresh data fetch.
  static void clearCache() {
    _cache.clear();
  }

  /// Clears cache entries for a specific date range
  static void clearCacheForRange(
    DateTime start,
    DateTime end, {
    double lat = defaultLat,
    double lon = defaultLon,
  }) {
    final endpoint = _determineEndpoint(start, end);
    final key = '$endpoint:avg:$lat,$lon:${_fmt(start)}:${_fmt(end)}';
    _cache.remove(key);
  }

  /// Merges two WeatherSummary objects by combining their temperature data
  static WeatherSummary _mergeWeatherSummaries(
    WeatherSummary historical,
    WeatherSummary recent,
  ) {
    // If both are empty, return empty
    if (historical.averageC == null &&
        historical.minC == null &&
        historical.maxC == null &&
        recent.averageC == null &&
        recent.minC == null &&
        recent.maxC == null) {
      return WeatherSummary.empty();
    }

    // If one is empty, return the other
    if (historical.averageC == null &&
        historical.minC == null &&
        historical.maxC == null) {
      return recent;
    }
    if (recent.averageC == null && recent.minC == null && recent.maxC == null) {
      return historical;
    }

    // Calculate weighted average (assuming roughly equal number of days)
    // Simple approach: average the averages
    double? mergedAvg;
    if (historical.averageC != null && recent.averageC != null) {
      mergedAvg = (historical.averageC! + recent.averageC!) / 2.0;
    } else if (historical.averageC != null) {
      mergedAvg = historical.averageC;
    } else if (recent.averageC != null) {
      mergedAvg = recent.averageC;
    }

    // Get overall min and max
    double? mergedMin;
    final List<double> mins = [];
    if (historical.minC != null && historical.minC!.isFinite)
      mins.add(historical.minC!);
    if (recent.minC != null && recent.minC!.isFinite) mins.add(recent.minC!);
    if (mins.isNotEmpty) {
      mins.sort();
      mergedMin = mins.first;
    }

    double? mergedMax;
    final List<double> maxs = [];
    if (historical.maxC != null && historical.maxC!.isFinite)
      maxs.add(historical.maxC!);
    if (recent.maxC != null && recent.maxC!.isFinite) maxs.add(recent.maxC!);
    if (maxs.isNotEmpty) {
      maxs.sort();
      mergedMax = maxs.last;
    }

    return WeatherSummary(
      averageC: mergedAvg,
      minC: mergedMin,
      maxC: mergedMax,
    );
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
