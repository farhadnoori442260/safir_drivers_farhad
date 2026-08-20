import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

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
    final maneuver = json['maneuver'] as Map<String, dynamic>? ?? {};
    final locationList = maneuver['location'] as List? ?? [0.0, 0.0];

    return StepInstruction(
      instruction: maneuver['type']?.toString() ?? 'straight',
      streetName: json['name']?.toString() ?? '',
      modifier: maneuver['modifier']?.toString() ?? 'straight',
      location: LatLng(
        (locationList[1] as num).toDouble(),
        (locationList[0] as num).toDouble(),
      ),
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class NavigationController extends ChangeNotifier {
  int routeVersion = 0;

  LatLng? activeDestination;
  LatLng? snappedDriverLocation;

  bool isRerouting = false;
  bool isNavigating = false;
  bool _isVoiceEnabled = true;

  double distanceFromRoute = 0.0;
  double distanceToNextStep = 0.0;

  final List<StepInstruction> _steps = [];
  final List<LatLng> routePoints = [];
  final Set<int> _spokenSteps = {};

  int _currentStepIndex = 0;
  String _activeLangCode = 'fa';

  String currentStreet = '';
  String currentModifier = 'straight';
  String _currentInstruction = '';
  IconData _currentTurnIcon = Icons.straight;

  bool get isVoiceEnabled => _isVoiceEnabled;
  int get distanceToNextTurn => distanceToNextStep.ceil();
  String get navigationInstruction =>
      _currentInstruction.isNotEmpty ? _currentInstruction : currentStreet;
  IconData get currentTurnIcon => _currentTurnIcon;
  List<LatLng> get currentRoutePoints => List.unmodifiable(routePoints);

  void toggleVoice() {
    _isVoiceEnabled = !_isVoiceEnabled;

    if (!_isVoiceEnabled) {
      VoiceGuidanceHelper.stop();
    }

    notifyListeners();
  }

  void speakInstruction(String text) {
    if (_isVoiceEnabled) {
      VoiceGuidanceHelper.speakStep(
        'straight',
        text,
        0,
        _activeLangCode,
      );
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

  Future<List<LatLng>> startNavigation([
    LatLng? start,
    LatLng? destination,
    String langCode = 'fa',
  ]) async {
    if (start == null || destination == null) {
      return [];
    }

    isNavigating = true;
    isRerouting = false;
    _activeLangCode = langCode;
    activeDestination = destination;

    _steps.clear();
    routePoints.clear();
    _spokenSteps.clear();
    _currentStepIndex = 0;
    distanceToNextStep = 0.0;
    distanceFromRoute = 0.0;

    notifyListeners();

    final route = await _fetchRoute(
      start: start,
      destination: destination,
    );

    if (route == null) {
      notifyListeners();
      return [];
    }

    _applyRoute(route);

    if (_steps.isNotEmpty && _isVoiceEnabled) {
      VoiceGuidanceHelper.speakStep(
        'straight',
        _steps.first.streetName,
        0,
        _activeLangCode,
      );
    }

    notifyListeners();
    return List.unmodifiable(routePoints);
  }

  void updateDriverPosition(
    LatLng driverLatLng, {
    String? langCode,
  }) {
    if (!isNavigating || routePoints.isEmpty) return;

    if (langCode != null) {
      _activeLangCode = langCode;
    }

    distanceFromRoute = _getDistanceFromRoute(driverLatLng);
    snappedDriverLocation = _getSnappedLocation(driverLatLng);

    if (_steps.isEmpty || _currentStepIndex >= _steps.length) {
      notifyListeners();
      return;
    }

    final currentStep = _steps[_currentStepIndex];

    final distance = Geolocator.distanceBetween(
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

    if (distanceFromRoute > 45 && !isRerouting) {
      _rerouteFromCurrentLocation(driverLatLng);
    }

    notifyListeners();
  }

  Future<Map<String, dynamic>?> _fetchRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&steps=true&geometries=geojson',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode != 200) {
        debugPrint(
          'osrm_error_status'.tr(args: [response.statusCode.toString()]),
        );
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;

      if (routes == null || routes.isEmpty) {
        return null;
      }

      return routes.first as Map<String, dynamic>;
    } catch (e) {
      debugPrint('osrm_error_fetch'.tr(args: [e.toString()]));
      return null;
    }
  }

  void _applyRoute(Map<String, dynamic> route) {
    final geometry = route['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List? ?? [];

    routePoints
      ..clear()
      ..addAll(
        coordinates.map(
          (point) {
            final values = point as List;
            return LatLng(
              (values[1] as num).toDouble(),
              (values[0] as num).toDouble(),
            );
          },
        ),
      );

    final legs = route['legs'] as List? ?? [];
    final firstLeg = legs.isNotEmpty ? legs.first as Map<String, dynamic> : {};
    final stepsJson = firstLeg['steps'] as List? ?? [];

    _steps
      ..clear()
      ..addAll(
        stepsJson.map(
          (step) => StepInstruction.fromJson(
            step as Map<String, dynamic>,
          ),
        ),
      );

    _currentStepIndex = 0;
    _spokenSteps.clear();

    if (_steps.isNotEmpty) {
      _updateCurrentStepInfo(notify: false);
    }

    routeVersion++;
  }

  Future<void> _rerouteFromCurrentLocation(LatLng from) async {
    if (activeDestination == null || isRerouting) return;

    isRerouting = true;
    notifyListeners();

    final route = await _fetchRoute(
      start: from,
      destination: activeDestination!,
    );

    if (route != null && isNavigating) {
      _applyRoute(route);
    }

    isRerouting = false;
    notifyListeners();
  }

  double _getDistanceFromRoute(LatLng rawLocation) {
    if (routePoints.isEmpty) return 0.0;

    var minDistance = double.infinity;

    for (final point in routePoints) {
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

  LatLng _getSnappedLocation(LatLng rawLocation) {
    if (routePoints.isEmpty) return rawLocation;

    var closestPoint = routePoints.first;
    var minDistance = Geolocator.distanceBetween(
      rawLocation.latitude,
      rawLocation.longitude,
      closestPoint.latitude,
      closestPoint.longitude,
    );

    for (final point in routePoints) {
      final distance = Geolocator.distanceBetween(
        rawLocation.latitude,
        rawLocation.longitude,
        point.latitude,
        point.longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestPoint = point;
      }
    }

    return minDistance <= 35 ? closestPoint : rawLocation;
  }

  void _updateCurrentStepInfo({bool notify = true}) {
    if (_currentStepIndex >= _steps.length) return;

    final step = _steps[_currentStepIndex];

    currentStreet = step.streetName;
    currentModifier = step.modifier;

    _currentInstruction = step.streetName.isNotEmpty
        ? step.streetName
        : _instructionFromModifier(step.modifier);

    _currentTurnIcon = _getIconFromModifier(step.modifier);

    if (notify) {
      notifyListeners();
    }
  }

  String _instructionFromModifier(String modifier) {
    switch (modifier) {
      case 'right':
      case 'slight right':
        return 'به راست بپیچید';
      case 'left':
      case 'slight left':
        return 'به چپ بپیچید';
      case 'uturn':
        return 'دور بزنید';
      default:
        return 'مستقیم بروید';
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
      case 'uturn':
        return Icons.u_turn_left;
      default:
        return Icons.straight;
    }
  }

  void stopNavigation() {
    isNavigating = false;
    isRerouting = false;

    _steps.clear();
    routePoints.clear();
    _spokenSteps.clear();

    _currentStepIndex = 0;
    activeDestination = null;
    snappedDriverLocation = null;

    distanceFromRoute = 0.0;
    distanceToNextStep = 0.0;
    currentStreet = '';
    currentModifier = 'straight';
    _currentInstruction = '';
    _currentTurnIcon = Icons.straight;

    VoiceGuidanceHelper.stop();
    notifyListeners();
  }
}
