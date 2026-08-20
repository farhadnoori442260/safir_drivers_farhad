import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:easy_localization/easy_localization.dart';
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
  int routeVersion = 0;
    LatLng? activeDestination;
  bool isRerouting = false;
  double distanceFromRoute = 0.0;
  bool isNavigating = false;
  bool _isVoiceEnabled = true;

  List<StepInstruction> _steps = [];
  List<LatLng> routePoints = []; // 📌 ذخیره نقاط خط مسیر برای کشیدن روی سرک
  int _currentStepIndex = 0;

  String currentStreet = '';
  String currentModifier = 'straight';
  double distanceToNextStep = 0.0;
  String _activeLangCode = 'fa';

  String _currentInstruction = '';
  IconData _currentTurnIcon = Icons.straight;

  LatLng? snappedDriverLocation; // 📌 موقعیت قفل‌شده راننده روی خیابان

  final Set<int> _spokenSteps = {};

  // 📌 Getters
  bool get isVoiceEnabled => _isVoiceEnabled;
  int get distanceToNextTurn => distanceToNextStep.toInt();
  String get navigationInstruction => _currentInstruction.isNotEmpty ? _currentInstruction : currentStreet;
  IconData get currentTurnIcon => _currentTurnIcon;

  void toggleVoice() {
    _isVoiceEnabled = !_isVoiceEnabled;
    if (!_isVoiceEnabled) {
      VoiceGuidanceHelper.stop();
    }
    notifyListeners();
  }

  void speakInstruction(String text) {
    if (_isVoiceEnabled) {
      VoiceGuidanceHelper.speakStep('straight', text, 0, _activeLangCode);
    }
  }

  void updateInstruction({
    required String instruction,
    required int distance,
    required IconData icon,
  }) {
    _currentInstruction = instruction;
    distanceToNextStep = distance.toDouble();
    _currentTurnIcon = icon;
    notifyListeners();
  }

  void startNavigationSimulated() {
    isNavigating = true;
    _currentStepIndex = 0;
    _spokenSteps.clear();
    notifyListeners();
  }

  /// 🚀 دریافت مسیر اصلی از OSRM و خروجی دادن لیست نقاط برای رسم خط روی نقشه
  Future<List<LatLng>> startNavigation([LatLng? start, LatLng? destination, String langCode = 'fa']) async {
    isNavigating = true;
    _activeLangCode = langCode;
    _steps.clear();
    routePoints.clear();
    _currentStepIndex = 0;
    _spokenSteps.clear();
    notifyListeners();

    if (start == null || destination == null) return [];
    activeDestination = destination;

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
          // 📌 استخراج نقاط خط مسیر جهت رسم خط رنگی روی خیابان
          final geometry = routes[0]['geometry']['coordinates'] as List;
          routePoints = geometry.map((pt) => LatLng(pt[1], pt[0])).toList();

          final legs = routes[0]['legs'] as List;
          final stepsJson = legs[0]['steps'] as List;

          _steps = stepsJson.map((s) => StepInstruction.fromJson(s)).toList();

          if (_steps.isNotEmpty) {
            _updateCurrentStepInfo();
            if (_isVoiceEnabled) {
              VoiceGuidanceHelper.speakStep('straight', _steps[0].streetName, 0, _activeLangCode);
            }
          }
        }
      } else {
        debugPrint('osrm_error_status'.tr(args: [response.statusCode.toString()]));
      }
    } catch (e) {
      debugPrint('osrm_error_fetch'.tr(args: [e.toString()]));
    }

    notifyListeners();
    return routePoints; // 📌 بازگرداندن نقاط خط مسیر به HomePage
  }

  /// 📍 بروزرسانی موقعیت راننده با قفل شدن روی نزدیک‌ترین نقطه خیابان
  void updateDriverPosition(LatLng driverLatLng, {String? langCode}) {
    if (!isNavigating || _steps.isEmpty || _currentStepIndex >= _steps.length) return;

    if (langCode != null) {
      _activeLangCode = langCode;
    }

    // 📌 قفل کردن موقعیت راننده روی خط خیابان
    snappedDriverLocation = _getSnappedLocation(driverLatLng);

    final currentStep = _steps[_currentStepIndex];

    double distance = Geolocator.distanceBetween(
      snappedDriverLocation!.latitude,
      snappedDriverLocation!.longitude,
      currentStep.location.latitude,
      currentStep.location.longitude,
    );

    distanceToNextStep = distance;

    if (distance <= 50 && !_spokenSteps.contains(_currentStepIndex)) {
      _spokenSteps.add(_currentStepIndex);
      if (_isVoiceEnabled) {
        VoiceGuidanceHelper.speakStep(
          currentStep.modifier,
          currentStep.streetName,
          distance.toInt(),
          _activeLangCode,
        );
      }
    }

    if (distance < 15 && _currentStepIndex < _steps.length - 1) {
      _currentStepIndex++;
      _updateCurrentStepInfo();
    }
    distanceFromRoute = _getDistanceFromRoute(driverLatLng);

    if (distanceFromRoute > 45 && !isRerouting) {
      _rerouteFromCurrentLocation(driverLatLng);
    }
    notifyListeners();
  }
  double _getDistanceFromRoute(LatLng rawLocation) {
    if (routePoints.isEmpty) return 0.0;

    double minDistance = double.infinity;

    for (var point in routePoints) {
      final distance = Geolocator.distanceBetween(
        rawLocation.latitude,
        rawLocation.longitude,
        point.latitude,
        point.longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    return minDistance;
  }
  Future<void> _rerouteFromCurrentLocation(LatLng from) async {
    if (activeDestination == null || isRerouting) return;

    isRerouting = true;

    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${from.longitude},${from.latitude};'
      '${activeDestination!.longitude},${activeDestination!.latitude}'
      '?overview=full&steps=true&geometries=geojson',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;

        if (routes.isNotEmpty) {
          final geometry = routes[0]['geometry']['coordinates'] as List;
          routePoints = geometry.map((pt) => LatLng(pt[1], pt[0])).toList();
          routeVersion++;

          final legs = routes[0]['legs'] as List;
          final stepsJson = legs[0]['steps'] as List;

          _steps = stepsJson.map((s) => StepInstruction.fromJson(s)).toList();
          _currentStepIndex = 0;
          _spokenSteps.clear();

          if (_steps.isNotEmpty) {
            _updateCurrentStepInfo();
          }
        }
      }
    } catch (e) {
      debugPrint('Reroute error: $e');
    }

    isRerouting = false;
    notifyListeners();
  }

  /// 📌 متد محاسبه و قفل کردن موقعیت خام GPS روی خط خیابان
  LatLng _getSnappedLocation(LatLng rawLocation) {
    if (routePoints.isEmpty) return rawLocation;

    LatLng closestPoint = routePoints.first;
    double minDistance = Geolocator.distanceBetween(
      rawLocation.latitude,
      rawLocation.longitude,
      closestPoint.latitude,
      closestPoint.longitude,
    );

    for (var point in routePoints) {
      double d = Geolocator.distanceBetween(
        rawLocation.latitude,
        rawLocation.longitude,
        point.latitude,
        point.longitude,
      );
      if (d < minDistance) {
        minDistance = d;
        closestPoint = point;
      }
    }

    // اگر انحراف GPS کمتر از ۳۵ متر باشد، موقعیت روی خط خیابان قفل می‌شود
    return minDistance < 35 ? closestPoint : rawLocation;
  }

  void _updateCurrentStepInfo() {
    if (_currentStepIndex < _steps.length) {
      final step = _steps[_currentStepIndex];
      currentStreet = step.streetName;
      currentModifier = step.modifier;
      _currentInstruction = step.streetName;
      _currentTurnIcon = _getIconFromModifier(step.modifier);
      notifyListeners();
    }
  }

  IconData _getIconFromModifier(String modifier) {
    switch (modifier) {
      case 'right':
      case 'slight right':
        return Icons.turn_right;
      case 'left':
      case 'slight left':
        return Icons.turn_left;
      default:
        return Icons.straight;
    }
  }

  void stopNavigation() {
    isNavigating = false;
    _steps.clear();
    routePoints.clear();
    _currentStepIndex = 0;
    _spokenSteps.clear();
    snappedDriverLocation = null;
    VoiceGuidanceHelper.stop();
    notifyListeners();
  }
}
