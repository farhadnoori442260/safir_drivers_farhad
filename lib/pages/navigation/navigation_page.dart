import 'dart:async';
import 'dart:ui' as ui;

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

  MapLibreMapController? mapController;
  StreamSubscription<Position>? _positionStream;
  Symbol? _driverSymbol;

  bool _mapStyleReady = false;
  bool _navigationStarted = false;
  bool _controllerListenerAdded = false;
  bool _driverIconAdded = false;
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

    await _addDriverArrowImage();
    await _startNavigation();
    await _startLiveDriverTracking();
  }

  Future<void> _addDriverArrowImage() async {
    if (mapController == null || _driverIconAdded) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const size = 120.0;
    const center = Offset(size / 2, size / 2);

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final arrowPath = Path()
      ..moveTo(center.dx, 7)
      ..lineTo(101, 103)
      ..quadraticBezierTo(99, 108, 93, 105)
      ..lineTo(center.dx, 87)
      ..lineTo(27, 105)
      ..quadraticBezierTo(21, 108, 19, 103)
      ..close();

    canvas.drawPath(
      arrowPath.shift(const Offset(0, 5)),
      shadowPaint,
    );

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(arrowPath, borderPaint);

    final fillPaint = Paint()
      ..color = SafirColors.primary
      ..style = PaintingStyle.fill;

    canvas.drawPath(arrowPath, fillPaint);

    final innerPath = Path()
      ..moveTo(center.dx, 26)
      ..lineTo(80, 89)
      ..lineTo(center.dx, 76)
      ..lineTo(40, 89)
      ..close();

    final innerPaint = Paint()
      ..color = Colors.white.withOpacity(0.22)
      ..style = PaintingStyle.fill;

    canvas.drawPath(innerPath, innerPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (bytes == null || mapController == null) return;

    await mapController!.addImage(
      _driverIconName,
      bytes.buffer.asUint8List(),
    );

    _driverIconAdded = true;
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
        lineColor: '#0B4F3A',
        lineWidth: 16.0,
        lineOpacity: 0.72,
      ),
    );

    await mapController!.addLine(
      LineOptions(
        geometry: points,
        lineColor: '#168A61',
        lineWidth: 11.0,
        lineOpacity: 1.0,
      ),
    );

    await mapController!.addLine(
      LineOptions(
        geometry: points,
        lineColor: '#4EE1A1',
        lineWidth: 4.0,
        lineOpacity: 0.95,
      ),
    );
  }

  void _navigationControllerChanged() {
    if (!mounted || !_mapStyleReady || mapController == null) return;

    final navigationController =
        Provider.of<NavigationController>(context, listen: false);

    if (navigationController.routeVersion == _lastRouteVersion) {
      return;
    }

    if (navigationController.currentRoutePoints.isEmpty) {
      return;
    }

    _lastRouteVersion = navigationController.routeVersion;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || mapController == null) return;

      await _drawRoute(navigationController.currentRoutePoints);
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

        final routeHeading = navigationController.driverRouteBearing;

        await _updateDriverMarker(
          driverLocation,
          heading: routeHeading,
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
    if (!mounted || mapController == null || !_driverIconAdded) return;

    final driverOptions = SymbolOptions(
      geometry: location,
      iconImage: _driverIconName,
      iconSize: 0.58,
      iconRotate: heading,
    );

    if (_driverSymbol == null) {
      _driverSymbol = await mapController!.addSymbol(driverOptions);

      await mapController!.setSymbolIconAllowOverlap(
        true,
      );

      await mapController!.setSymbolIconIgnorePlacement(
        true,
      );
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
