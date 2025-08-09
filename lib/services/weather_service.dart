import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  // Carmen, Davao del Norte (approximate)
  static const double defaultLat = 7.3600;
  static const double defaultLon = 125.7000;

  static Future<WeatherSummary> getAverageTemperature({
    required DateTime start,
    required DateTime end,
    double lat = defaultLat,
    double lon = defaultLon,
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
      final maxV =
          i < tempsMax.length ? (tempsMax[i] as num).toDouble() : double.nan;
      final minV =
          i < tempsMin.length ? (tempsMin[i] as num).toDouble() : double.nan;
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
    final doubles = list.map((e) => (e as num).toDouble()).toList();
    doubles.sort();
    return doubles.first;
  }

  static double? _safeMax(List list) {
    if (list.isEmpty) return null;
    final doubles = list.map((e) => (e as num).toDouble()).toList();
    doubles.sort();
    return doubles.last;
  }
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
