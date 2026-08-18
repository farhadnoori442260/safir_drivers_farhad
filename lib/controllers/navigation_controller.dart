import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:easy_localization/easy_localization.dart'; // 📌 اتصال به easy_localization
import '../helpers/voice_guidance_helper.dart';

class StepInstruction {
  final String instruction;
  final String streetName;
  final String modifier;
  final LatLng location;
  final double distance;

  StepInstruction({
    required this.instruction,
    required this.streetName,
    required this.modifier,
    required this.location,
    required this.distance,
  });

  factory StepInstruction.fromJson(Map<String, dynamic> json) {
    final maneuver = json['maneuver'];
    final locationList = maneuver['location'];
    return StepInstruction(
      instruction: maneuver['type'] ?? 'straight',
      streetName: json['name'] ?? '',
      modifier: maneuver['modifier'] ?? 'straight',
      location: LatLng(locationList[1], locationList[0]),
      distance: (json['distance'] as num).toDouble(),
    );
  }
}

class NavigationController extends ChangeNotifier {
  bool isNavigating = false;
  List<StepInstruction> _steps = [];
  int _currentStepIndex = 0;

  String currentStreet = '';
  String currentModifier = 'straight';
  double distanceToNextStep = 0.0;
  String _activeLangCode = 'fa';

  final Set<int> _spokenSteps = {};

  /// 🚀 دریافت مسیر از OSRM و شروع مسیریابی
  Future<void> startNavigation(LatLng start, LatLng destination, String langCode) async {
    isNavigating = true;
    _activeLangCode = langCode;
    _steps.clear();
    _currentStepIndex = 0;
    _spokenSteps.clear();
    notifyListeners();

    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}'
      '?overview=full&steps=true&geometries=geojson',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;

        if (routes.isNotEmpty) {
          final legs = routes[0]['legs'] as List;
          final stepsJson = legs[0]['steps'] as List;

          _steps = stepsJson.map((s) => StepInstruction.fromJson(s)).toList();

          if (_steps.isNotEmpty) {
            _updateCurrentStepInfo();
            VoiceGuidanceHelper.speakStep('straight', _steps[0].streetName, 0, _activeLangCode);
          }
        }
      } else {
        debugPrint('osrm_error_status'.tr(args: [response.statusCode.toString()]));
      }
    } catch (e) {
      debugPrint('osrm_error_fetch'.tr(args: [e.toString()]));
    }
  }

  /// 📍 بروزرسانی موقعیت راننده و بررسی فاصله تا مانور بعدی
  void updateDriverPosition(LatLng driverLatLng, {String? langCode}) {
    if (!isNavigating || _steps.isEmpty || _currentStepIndex >= _steps.length) return;

    if (langCode != null) {
      _activeLangCode = langCode;
    }

    final currentStep = _steps[_currentStepIndex];

    double distance = Geolocator.distanceBetween(
      driverLatLng.latitude,
      driverLatLng.longitude,
      currentStep.location.latitude,
      currentStep.location.longitude,
    );

    distanceToNextStep = distance;

    if (distance <= 50 && !_spokenSteps.contains(_currentStepIndex)) {
      _spokenSteps.add(_currentStepIndex);
      VoiceGuidanceHelper.speakStep(
        currentStep.modifier,
        currentStep.streetName,
        distance.toInt(),
        _activeLangCode,
      );
    }

    if (distance < 15 && _currentStepIndex < _steps.length - 1) {
      _currentStepIndex++;
      _updateCurrentStepInfo();
    }

    notifyListeners();
  }

  void _updateCurrentStepInfo() {
    if (_currentStepIndex < _steps.length) {
      final step = _steps[_currentStepIndex];
      currentStreet = step.streetName;
      currentModifier = step.modifier;
      notifyListeners();
    }
  }

  /// 🛑 متوقف کردن مسیریابی
  void stopNavigation() {
    isNavigating = false;
    _steps.clear();
    _currentStepIndex = 0;
    _spokenSteps.clear();
    VoiceGuidanceHelper.stop();
    notifyListeners();
  }
}
