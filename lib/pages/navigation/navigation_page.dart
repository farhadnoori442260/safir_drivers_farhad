import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import '../../controllers/navigation_controller.dart';
import '../../utils/app_colors.dart';

class NavigationPage extends StatefulWidget {
  final LatLng start;
  final LatLng destination;

  const NavigationPage({
    super.key,
    required this.start,
    required this.destination,
  });

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  static const String _driverIconName = 'safir-driver-arrow';
  static const String _destinationIconName = 'safir-destination-pin';
  static const String _leftTurnIconName = 'safir-turn-left';
  static const String _rightTurnIconName = 'safir-turn-right';
  static const String _straightIconName = 'safir-turn-straight';
  static const String _uTurnIconName = 'safir-turn-uturn';

  MapLibreMapController? mapController;
  StreamSubscription<Position>? _positionStream;

  Symbol? _driverSymbol;
  Symbol? _destinationSymbol;
  Symbol? _streetNameSymbol;

  final List<Symbol> _turnSymbols = [];

  bool _mapStyleReady = false;
  bool _navigationStarted = false;
  bool _controllerListenerAdded = false;
  bool _iconsAdded = false;

  bool _cameraFollowing = true;
  bool _isUpdatingMap = false;
  bool _isProgrammaticCameraMove = false;

  int _lastRouteVersion = 0;

  void _onMapCreated(MapLibreMapController controller) {
    mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    if (!mounted) return;

    _mapStyleReady = true;

    final navigationController =
        Provider.of<NavigationController>(context, listen: false);

    if (!_controllerListenerAdded) {
      navigationController.addListener(_navigationControllerChanged);
      _controllerListenerAdded = true;
    }

    await _addMapImages();
    await _startNavigation();
    await _startLiveDriverTracking();
  }

  Future<void> _addMapImages() async {
    if (mapController == null || _iconsAdded) return;

    await _addCanvasImage(
      _driverIconName,
      _drawDriverArrow,
      width: 120,
      height: 120,
    );

    await _addCanvasImage(
      _destinationIconName,
      _drawDestinationPin,
      width: 100,
      height: 120,
    );

    await _addCanvasImage(
      _leftTurnIconName,
      (canvas, size) => _drawTurnArrow(
        canvas,
        size,
        direction: _TurnDirection.left,
      ),
      width: 96,
      height: 96,
    );

    await _addCanvasImage(
      _rightTurnIconName,
      (canvas, size) => _drawTurnArrow(
        canvas,
        size,
        direction: _TurnDirection.right,
      ),
      width: 96,
      height: 96,
    );

    await _addCanvasImage(
      _straightIconName,
      (canvas, size) => _drawTurnArrow(
        canvas,
        size,
        direction: _TurnDirection.straight,
      ),
      width: 96,
      height: 96,
    );

    await _addCanvasImage(
      _uTurnIconName,
      (canvas, size) => _drawTurnArrow(
        canvas,
        size,
        direction: _TurnDirection.uTurn,
      ),
      width: 96,
      height: 96,
    );

    _iconsAdded = true;
  }

  Future<void> _addCanvasImage(
    String name,
    void Function(Canvas canvas, Size size) painter, {
    required int width,
    required int height,
  }) async {
    if (mapController == null) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(width.toDouble(), height.toDouble());

    painter(canvas, size);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (bytes == null || mapController == null) return;

    await mapController!.addImage(
      name,
      bytes.buffer.asUint8List(),
    );
  }

  void _drawDriverArrow(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final path = Path()
      ..moveTo(center.dx, 8)
      ..lineTo(size.width - 18, size.height - 19)
      ..quadraticBezierTo(
        size.width - 16,
        size.height - 10,
        size.width - 27,
        size.height - 15,
      )
      ..lineTo(center.dx, size.height - 35)
      ..lineTo(27, size.height - 15)
      ..quadraticBezierTo(16, size.height - 10, 18, size.height - 19)
      ..close();

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.26)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawPath(path.shift(const Offset(0, 5)), shadowPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, borderPaint);

    final fillPaint = Paint()
      ..color = SafirColors.primary
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);
  }

  void _drawDestinationPin(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final top = 8.0;
    final pinBottom = size.height - 8.0;

    final pinPath = Path()
      ..moveTo(centerX, pinBottom)
      ..cubicTo(
        12,
        size.height - 42,
        10,
        22,
        centerX,
        top,
      )
      ..cubicTo(
        size.width - 10,
        22,
        size.width - 12,
        size.height - 42,
        centerX,
        pinBottom,
      )
      ..close();

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawPath(pinPath.shift(const Offset(0, 4)), shadowPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;

    canvas.drawPath(pinPath, borderPaint);

    final fillPaint = Paint()..color = const Color(0xFFE84242);

    canvas.drawPath(pinPath, fillPaint);

    final circlePaint = Paint()..color = Colors.white;

    canvas.drawCircle(
      Offset(centerX, 43),
      13,
      circlePaint,
    );

    final dotPaint = Paint()..color = const Color(0xFFE84242);

    canvas.drawCircle(
      Offset(centerX, 43),
      7,
      dotPaint,
    );
  }

  void _drawTurnArrow(
    Canvas canvas,
    Size size, {
    required _TurnDirection direction,
  }) {
    final center = Offset(size.width / 2, size.height / 2);

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final path = Path();

    if (direction == _TurnDirection.straight) {
      path
        ..moveTo(center.dx - 12, size.height - 15)
        ..lineTo(center.dx - 12, 35)
        ..lineTo(23, 35)
        ..lineTo(center.dx, 10)
        ..lineTo(73, 35)
        ..lineTo(center.dx + 12, 35)
        ..lineTo(center.dx + 12, size.height - 15)
        ..close();
    } else if (direction == _TurnDirection.left) {
      path
        ..moveTo(78, size.height - 16)
        ..lineTo(56, size.height - 16)
        ..lineTo(56, 49)
        ..cubicTo(56, 40, 49, 35, 39, 35)
        ..lineTo(31, 35)
        ..lineTo(31, 49)
        ..lineTo(10, 27)
        ..lineTo(31, 5)
        ..lineTo(31, 20)
        ..lineTo(40, 20)
        ..cubicTo(61, 20, 78, 33, 78, 51)
        ..close();
    } else if (direction == _TurnDirection.right) {
      path
        ..moveTo(18, size.height - 16)
        ..lineTo(40, size.height - 16)
        ..lineTo(40, 49)
        ..cubicTo(40, 40, 47, 35, 57, 35)
        ..lineTo(65, 35)
        ..lineTo(65, 49)
        ..lineTo(86, 27)
        ..lineTo(65, 5)
        ..lineTo(65, 20)
        ..lineTo(56, 20)
        ..cubicTo(35, 20, 18, 33, 18, 51)
        ..close();
    } else {
      path
        ..moveTo(65, size.height - 13)
        ..lineTo(43, size.height - 13)
        ..lineTo(43, 54)
        ..cubicTo(43, 42, 51, 34, 62, 34)
        ..lineTo(70, 34)
        ..lineTo(70, 49)
        ..lineTo(89, 27)
        ..lineTo(70, 5)
        ..lineTo(70, 20)
        ..lineTo(61, 20)
        ..cubicTo(39, 20, 23, 35, 23, 55)
        ..lineTo(23, size.height - 13)
        ..lineTo(10, size.height - 13)
        ..lineTo(37, size.height - 2)
        ..close();
    }

    canvas.drawPath(path.shift(const Offset(0, 3)), shadowPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, borderPaint);

    final fillPaint = Paint()
      ..color = const Color(0xFF168A61)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);
  }

  Future<void> _startNavigation() async {
    if (!_mapStyleReady || _navigationStarted || mapController == null) {
      return;
    }

    _navigationStarted = true;

    final navigationController =
        Provider.of<NavigationController>(context, listen: false);

    final routePoints = await navigationController.startNavigation(
      widget.start,
      widget.destination,
      context.locale.languageCode,
    );

    if (!mounted || mapController == null || routePoints.isEmpty) {
      _navigationStarted = false;
      return;
    }

    _lastRouteVersion = navigationController.routeVersion;

    await _drawRoute(routePoints);
    await _drawRouteDecorations(navigationController);

    await _updateDriverMarker(
      widget.start,
      heading: navigationController.driverRouteBearing,
      moveCamera: true,
    );
  }

  Future<void> _drawRoute(List<LatLng> points) async {
    if (!mounted || mapController == null || points.isEmpty) return;

    await mapController!.clearLines();

    await mapController!.addLine(
      LineOptions(
        geometry: points,
        lineColor: '#07553F',
        lineWidth: 18.0,
        lineOpacity: 0.78,
      ),
    );

    await mapController!.addLine(
      LineOptions(
        geometry: points,
        lineColor: '#10B981',
        lineWidth: 12.0,
        lineOpacity: 1.0,
      ),
    );

    await mapController!.addLine(
      LineOptions(
        geometry: points,
        lineColor: '#B8FFE3',
        lineWidth: 3.5,
        lineOpacity: 0.95,
      ),
    );
  }

  Future<void> _drawRouteDecorations(
    NavigationController navigationController,
  ) async {
    if (mapController == null) return;

    await _clearRouteDecorations();

    _destinationSymbol = await mapController!.addSymbol(
      SymbolOptions(
        geometry: widget.destination,
        iconImage: _destinationIconName,
        iconSize: 0.68,
      ),
    );

    await mapController!.setSymbolIconAllowOverlap(true);
    await mapController!.setSymbolIconIgnorePlacement(true);

    final steps = navigationController.routeSteps;

    for (var index = 0; index < steps.length; index++) {
      final step = steps[index];

      if (step.distance < 18) continue;
      if (index == 0 && step.modifier == 'straight') continue;

      final iconName = _turnIconName(step.modifier);

      final turnSymbol = await mapController!.addSymbol(
        SymbolOptions(
          geometry: step.location,
          iconImage: iconName,
          iconSize: 0.44,
          iconRotate: _routeBearingAt(
            step.location,
            navigationController.currentRoutePoints,
          ),
        ),
      );

      _turnSymbols.add(turnSymbol);
    }

    final firstStreetStep = steps.firstWhere(
      (step) => step.streetName.trim().isNotEmpty,
      orElse: () => StepInstruction(
        instruction: 'straight',
        streetName: '',
        modifier: 'straight',
        location: widget.start,
        distance: 0,
      ),
    );

    if (firstStreetStep.streetName.trim().isNotEmpty) {
      _streetNameSymbol = await mapController!.addSymbol(
        SymbolOptions(
          geometry: firstStreetStep.location,
          textField: firstStreetStep.streetName,
          textSize: 14.0,
          textColor: '#0F2B22',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.5,
          textAnchor: 'bottom',
          textOffset: const Offset(0, -2.2),
        ),
      );
    }
  }

  String _turnIconName(String modifier) {
    switch (modifier) {
      case 'left':
      case 'slight left':
      case 'sharp left':
        return _leftTurnIconName;
      case 'right':
      case 'slight right':
      case 'sharp right':
        return _rightTurnIconName;
      case 'uturn':
        return _uTurnIconName;
      default:
        return _straightIconName;
    }
  }

  double _routeBearingAt(
    LatLng location,
    List<LatLng> points,
  ) {
    if (points.length < 2) return 0;

    var closestIndex = 0;
    var closestDistance = double.infinity;

    for (var index = 0; index < points.length; index++) {
      final point = points[index];

      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        point.latitude,
        point.longitude,
      );

      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = index;
      }
    }

    final nextIndex = closestIndex < points.length - 1
        ? closestIndex + 1
        : closestIndex;

    final previousIndex = closestIndex > 0
        ? closestIndex - 1
        : closestIndex;

    final start = points[previousIndex];
    final end = points[nextIndex];

    final latitudeRadians = start.latitude * 0.017453292519943295;
    final endLatitudeRadians = end.latitude * 0.017453292519943295;
    final deltaLongitude =
        (end.longitude - start.longitude) * 0.017453292519943295;

    final y = math.sin(deltaLongitude) * math.cos(endLatitudeRadians);

final x =
    (math.cos(latitudeRadians) * math.sin(endLatitudeRadians)) -
    (math.sin(latitudeRadians) *
        math.cos(endLatitudeRadians) *
        math.cos(deltaLongitude));

final heading = math.atan2(y, x) * 57.29577951308232;

    return (heading + 360.0) % 360.0;
  }

  Future<void> _clearRouteDecorations() async {
    if (mapController == null) return;

    for (final symbol in _turnSymbols) {
      await mapController!.removeSymbol(symbol);
    }

    _turnSymbols.clear();

    if (_destinationSymbol != null) {
      await mapController!.removeSymbol(_destinationSymbol!);
      _destinationSymbol = null;
    }

    if (_streetNameSymbol != null) {
      await mapController!.removeSymbol(_streetNameSymbol!);
      _streetNameSymbol = null;
    }
  }

  void _navigationControllerChanged() {
    if (!mounted || !_mapStyleReady || mapController == null) return;

    final navigationController =
        Provider.of<NavigationController>(context, listen: false);

    if (navigationController.routeVersion == _lastRouteVersion) return;
    if (navigationController.currentRoutePoints.isEmpty) return;

    _lastRouteVersion = navigationController.routeVersion;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || mapController == null) return;

      await _drawRoute(navigationController.currentRoutePoints);
      await _drawRouteDecorations(navigationController);
    });
  }

  Future<void> _startLiveDriverTracking() async {
    if (!_mapStyleReady || mapController == null) return;

    await _positionStream?.cancel();

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((Position position) async {
      if (!mounted || mapController == null || _isUpdatingMap) return;

      _isUpdatingMap = true;

      try {
        final rawLocation = LatLng(
          position.latitude,
          position.longitude,
        );

        final navigationController =
            Provider.of<NavigationController>(context, listen: false);

        navigationController.updateDriverPosition(
          rawLocation,
          langCode: context.locale.languageCode,
        );

        final driverLocation =
            navigationController.snappedDriverLocation ?? rawLocation;

        await _updateDriverMarker(
          driverLocation,
          heading: navigationController.driverRouteBearing,
          moveCamera: _cameraFollowing,
        );
      } finally {
        _isUpdatingMap = false;
      }
    });
  }

  Future<void> _updateDriverMarker(
    LatLng location, {
    required double heading,
    required bool moveCamera,
  }) async {
    if (!mounted || mapController == null || !_iconsAdded) return;

    final driverOptions = SymbolOptions(
      geometry: location,
      iconImage: _driverIconName,
      iconSize: 0.58,
      iconRotate: heading,
    );

    if (_driverSymbol == null) {
      _driverSymbol = await mapController!.addSymbol(driverOptions);

      await mapController!.setSymbolIconAllowOverlap(true);
      await mapController!.setSymbolIconIgnorePlacement(true);
    } else {
      await mapController!.updateSymbol(
        _driverSymbol!,
        driverOptions,
      );
    }

    if (!moveCamera || mapController == null) return;

    await _moveCameraToDriver(
      location,
      heading: heading,
    );
  }

  Future<void> _moveCameraToDriver(
    LatLng location, {
    required double heading,
  }) async {
    if (mapController == null) return;

    _isProgrammaticCameraMove = true;

    try {
      await mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: location,
            zoom: 17.5,
            bearing: heading,
            tilt: 50.0,
          ),
        ),
        duration: const Duration(milliseconds: 650),
      );
    } finally {
      Future.delayed(
        const Duration(milliseconds: 800),
        () {
          if (mounted) {
            _isProgrammaticCameraMove = false;
          }
        },
      );
    }
  }

  Future<void> _showFullRoute() async {
    if (mapController == null) return;

    final navigationController =
        Provider.of<NavigationController>(context, listen: false);

    final points = navigationController.currentRoutePoints;

    if (points.length < 2) return;

    setState(() {
      _cameraFollowing = false;
    });

    await mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        _boundsFromPoints(points),
        left: 54.0,
        top: 160.0,
        right: 54.0,
        bottom: 180.0,
      ),
      duration: const Duration(milliseconds: 700),
    );
  }

  Future<void> _goToStart() async {
    if (mapController == null) return;

    setState(() {
      _cameraFollowing = false;
    });

    await mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: widget.start,
          zoom: 17.0,
          tilt: 35.0,
        ),
      ),
      duration: const Duration(milliseconds: 600),
    );
  }

  Future<void> _followDriver() async {
    final navigationController =
        Provider.of<NavigationController>(context, listen: false);

    final location =
        navigationController.snappedDriverLocation ?? widget.start;

    setState(() {
      _cameraFollowing = true;
    });

    await _moveCameraToDriver(
      location,
      heading: navigationController.driverRouteBearing,
    );
  }

  LatLngBounds _boundsFromPoints(List<LatLng> points) {
    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLatitude) minLatitude = point.latitude;
      if (point.latitude > maxLatitude) maxLatitude = point.latitude;
      if (point.longitude < minLongitude) minLongitude = point.longitude;
      if (point.longitude > maxLongitude) maxLongitude = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLatitude, minLongitude),
      northeast: LatLng(maxLatitude, maxLongitude),
    );
  }

  Future<void> _stopNavigation() async {
    await _positionStream?.cancel();

    final navigationController =
        Provider.of<NavigationController>(context, listen: false);

    if (_controllerListenerAdded) {
      navigationController.removeListener(_navigationControllerChanged);
      _controllerListenerAdded = false;
    }

    navigationController.stopNavigation();

    if (mapController != null) {
      await mapController!.clearLines();
      await _clearRouteDecorations();

      if (_driverSymbol != null) {
        await mapController!.removeSymbol(_driverSymbol!);
        _driverSymbol = null;
      }
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    final navigationController =
        Provider.of<NavigationController>(context, listen: false);

    if (_controllerListenerAdded) {
      navigationController.removeListener(_navigationControllerChanged);
    }

    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onCameraIdle: () {
              if (!_isProgrammaticCameraMove && mounted) {
                setState(() {
                  _cameraFollowing = false;
                });
              }
            },
            styleString: 'assets/map/style.json',
            initialCameraPosition: CameraPosition(
              target: widget.start,
              zoom: 16.0,
            ),
            myLocationEnabled: false,
            trackCameraPosition: true,
          ),

          if (!_cameraFollowing)
            Positioned(
              left: 20,
              right: 20,
              bottom: 34,
              child: SafeArea(
                child: ElevatedButton.icon(
                  onPressed: _followDriver,
                  icon: const Icon(Icons.navigation),
                  label: const Text('بازگشت به مسیر'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SafirColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 6,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            right: 16,
            bottom: 112,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapActionButton(
                    icon: Icons.alt_route,
                    tooltip: 'نمایش کل مسیر',
                    onPressed: _showFullRoute,
                  ),
                  const SizedBox(height: 10),
                  _MapActionButton(
                    icon: Icons.home_outlined,
                    tooltip: 'بازگشت به مبدا',
                    onPressed: _goToStart,
                  ),
                  const SizedBox(height: 10),
                  _MapActionButton(
                    icon: Icons.my_location,
                    tooltip: 'بازگشت به راننده',
                    iconColor: SafirColors.primary,
                    onPressed: _followDriver,
                  ),
                ],
              ),
            ),
          ),

          Consumer<NavigationController>(
            builder: (context, controller, child) {
              if (!controller.isNavigating) {
                return const SizedBox.shrink();
              }

              return Positioned(
                top: 20,
                left: 16,
                right: 16,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SafirColors.primary,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          controller.currentTurnIcon,
                          color: Colors.white,
                          size: 34,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${controller.distanceToNextTurn} ${'meters'.tr()}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                controller.navigationInstruction,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: controller.toggleVoice,
                          icon: Icon(
                            controller.isVoiceEnabled
                                ? Icons.volume_up
                                : Icons.volume_off,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          onPressed: _stopNavigation,
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

enum _TurnDirection {
  left,
  right,
  straight,
  uTurn,
}
class _MapActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? iconColor;

  const _MapActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 5,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: iconColor ?? Colors.black87,
        ),
      ),
    );
  }
}
