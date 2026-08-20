import 'dart:convert';
import 'dart:math' as math;

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
  LatLng? rawDriverLocation;

  bool isRerouting = false;
  bool isNavigating = false;
  bool _isVoiceEnabled = true;

  double distanceFromRoute = 0.0;
  double distanceToNextStep = 0.0;
  double driverRouteBearing = 0.0;

  final List<StepInstruction> _steps = [];
  final List<LatLng> routePoints = [];
  final Set<int> _spokenSteps = {};

  int _currentStepIndex = 0;
  int _lastMatchedSegmentIndex = 0;
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
    _lastMatchedSegmentIndex = 0;
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
    rawDriverLocation = start;
    snappedDriverLocation = start;

    _steps.clear();
    routePoints.clear();
    _spokenSteps.clear();

    _currentStepIndex = 0;
    _lastMatchedSegmentIndex = 0;

    distanceToNextStep = 0.0;
    distanceFromRoute = 0.0;
    driverRouteBearing = 0.0;

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

    if (routePoints.length > 1) {
      driverRouteBearing = _bearingBetween(
        routePoints[0],
        routePoints[1],
      );
    }

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
    if (!isNavigating || routePoints.length < 2) {
      return;
    }

    if (langCode != null) {
      _activeLangCode = langCode;
    }

    rawDriverLocation = driverLatLng;

    final match = _findClosestPointOnRoute(driverLatLng);

    distanceFromRoute = match.distance;
    _lastMatchedSegmentIndex = match.segmentIndex;

    if (match.distance <= 40) {
      snappedDriverLocation = match.point;
      driverRouteBearing = match.bearing;
    } else {
      snappedDriverLocation = driverLatLng;
    }

    if (_steps.isEmpty || _currentStepIndex >= _steps.length) {
      if (distanceFromRoute > 50 && !isRerouting) {
        _rerouteFromCurrentLocation(driverLatLng);
      }

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

    if (distanceFromRoute > 50 && !isRerouting) {
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
    final firstLeg = legs.isNotEmpty
        ? legs.first as Map<String, dynamic>
        : <String, dynamic>{};

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
    _lastMatchedSegmentIndex = 0;
    _spokenSteps.clear();

    if (_steps.isNotEmpty) {
      _updateCurrentStepInfo(notify: false);
    }

    routeVersion++;
  }

  Future<void> _rerouteFromCurrentLocation(LatLng from) async {
    if (activeDestination == null || isRerouting) {
      return;
    }

    isRerouting = true;
    notifyListeners();

    final route = await _fetchRoute(
      start: from,
      destination: activeDestination!,
    );

    if (route != null && isNavigating) {
      _applyRoute(route);

      if (routePoints.length > 1) {
        driverRouteBearing = _bearingBetween(
          routePoints[0],
          routePoints[1],
        );
      }
    }

    isRerouting = false;
    notifyListeners();
  }

  _RouteMatch _findClosestPointOnRoute(LatLng location) {
    var closestPoint = routePoints.first;
    var closestDistance = double.infinity;
    var closestSegmentIndex = 0;
    var closestBearing = 0.0;

    final startIndex = math.max(0, _lastMatchedSegmentIndex - 25);
    final endIndex = math.min(
      routePoints.length - 2,
      _lastMatchedSegmentIndex + 100,
    );

    for (var i = startIndex; i <= endIndex; i++) {
      final start = routePoints[i];
      final end = routePoints[i + 1];

      final projectedPoint = _projectPointOnSegment(
        location,
        start,
        end,
      );

      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        projectedPoint.latitude,
        projectedPoint.longitude,
      );

      if (distance < closestDistance) {
        closestDistance = distance;
        closestPoint = projectedPoint;
        closestSegmentIndex = i;
        closestBearing = _bearingBetween(start, end);
      }
    }

    return _RouteMatch(
      point: closestPoint,
      distance: closestDistance,
      segmentIndex: closestSegmentIndex,
      bearing: closestBearing,
    );
  }

  LatLng _projectPointOnSegment(
    LatLng point,
    LatLng segmentStart,
    LatLng segmentEnd,
  ) {
    final latitudeRadians = point.latitude * math.pi / 180.0;
    final metersPerLatitudeDegree = 111132.0;
    final metersPerLongitudeDegree =
        111320.0 * math.cos(latitudeRadians);

    final pointX = point.longitude * metersPerLongitudeDegree;
    final pointY = point.latitude * metersPerLatitudeDegree;

    final startX = segmentStart.longitude * metersPerLongitudeDegree;
    final startY = segmentStart.latitude * metersPerLatitudeDegree;

    final endX = segmentEnd.longitude * metersPerLongitudeDegree;
    final endY = segmentEnd.latitude * metersPerLatitudeDegree;

    final deltaX = endX - startX;
    final deltaY = endY - startY;
    final lengthSquared = (deltaX * deltaX) + (deltaY * deltaY);

    if (lengthSquared == 0) {
      return segmentStart;
    }

    var projection = (
          ((pointX - startX) * deltaX) +
          ((pointY - startY) * deltaY)
        ) /
        lengthSquared;

    projection = projection.clamp(0.0, 1.0);

    final projectedX = startX + (projection * deltaX);
    final projectedY = startY + (projection * deltaY);

    return LatLng(
      projectedY / metersPerLatitudeDegree,
      projectedX / metersPerLongitudeDegree,
    );
  }

  double _bearingBetween(LatLng start, LatLng end) {
    final lat1 = start.latitude * math.pi / 180.0;
    final lat2 = end.latitude * math.pi / 180.0;
    final deltaLongitude =
        (end.longitude - start.longitude) * math.pi / 180.0;

    final y = math.sin(deltaLongitude) * math.cos(lat2);

    final x =
        (math.cos(lat1) * math.sin(lat2)) -
        (math.sin(lat1) * math.cos(lat2) * math.cos(deltaLongitude));

    final bearing = math.atan2(y, x) * 180.0 / math.pi;

    return (bearing + 360.0) % 360.0;
  }

  void _updateCurrentStepInfo({bool notify = true}) {
    if (_currentStepIndex >= _steps.length) {
      return;
    }

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
      case 'sharp right':
        return 'به راست بپیچید';
      case 'left':
      case 'slight left':
      case 'sharp left':
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
      case 'sharp right':
        return Icons.turn_right;
      case 'left':
      case 'slight left':
      case 'sharp left':
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
    _lastMatchedSegmentIndex = 0;

    activeDestination = null;
    rawDriverLocation = null;
    snappedDriverLocation = null;

    distanceFromRoute = 0.0;
    distanceToNextStep = 0.0;
    driverRouteBearing = 0.0;

    currentStreet = '';
    currentModifier = 'straight';
    _currentInstruction = '';
    _currentTurnIcon = Icons.straight;

    VoiceGuidanceHelper.stop();
    notifyListeners();
  }
}

class _RouteMatch {
  final LatLng point;
  final double distance;
  final int segmentIndex;
  final double bearing;

  const _RouteMatch({
    required this.point,
    required this.distance,
    required this.segmentIndex,
    required this.bearing,
  });
}
