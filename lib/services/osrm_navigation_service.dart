import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart'; // 📌 جایگزینی google_maps_flutter با maplibre_gl
import '../models/navigation_step_model.dart';

class OSRMNavigationService {
  /// دریافت لیست گام‌ها و مانورهای مسیر از API رایگان OSRM
  static Future<List<NavigationStepModel>> getRouteSteps(
    LatLng origin,
    LatLng destination,
  ) async {
    // ارسال پارامتر steps=true برای دریافت اطلاعات دقیق پیچ‌ها و نام خیابان‌ها
    final String url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&steps=true';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final legs = data['routes'][0]['legs'][0];
          final stepsJson = legs['steps'] as List;

          List<NavigationStepModel> steps = [];
          for (var step in stepsJson) {
            steps.add(NavigationStepModel.fromJson(step));
          }
          return steps;
        }
      } else {
        debugPrint('خطای OSRM: کد وضعیت ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('خطا در برقراری ارتباط با OSRM: $e');
    }

    return [];
  }
}
