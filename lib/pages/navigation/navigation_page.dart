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

  int _lastRouteVersion = 0;
  double _lastHeading = 0.0;

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
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final arrowPath = Path()
      ..moveTo(center.dx, 8)
      ..lineTo(100, 102)
      ..lineTo(center.dx, 84)
      ..lineTo(20, 102)
      ..close();

    canvas.drawPath(arrowPath.shift(const Offset(0, 4)), shadowPaint);

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

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

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
      heading: _lastHeading,
      moveCamera: true,
    );
  }

  Future<void> _drawRoute(List<LatLng> points) async {
    if (!mounted || mapController == null || points.isEmpty) return;

    await mapController!.clearLines();

    await mapController!.addLine(
      LineOptions(
        geometry: points,
        lineColor: '#1B7A57',
        lineWidth: 7.0,
        lineOpacity: 0.9,
      ),
    );
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

        if (position.heading.isFinite &&
            position.heading >= 0 &&
            position.heading <= 360) {
          _lastHeading = position.heading;
        }

        await _updateDriverMarker(
          driverLocation,
          heading: _lastHeading,
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

    final options = SymbolOptions(
      geometry: location,
      iconImage: _driverIconName,
      iconSize: 0.55,
      iconRotate: heading,
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
    );

    if (_driverSymbol == null) {
      _driverSymbol = await mapController!.addSymbol(options);
    } else {
      await mapController!.updateSymbol(_driverSymbol!, options);
    }

    if (!moveCamera || mapController == null) return;

    await mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: location,
          zoom: 17.5,
          bearing: heading,
          tilt: 50.0,
        ),
      ),
      duration: const Duration(milliseconds: 700),
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
              _cameraFollowing = false;
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
            bottom: 118,
            child: SafeArea(
              child: FloatingActionButton(
                heroTag: 'follow_driver_button',
                mini: true,
                backgroundColor: Colors.white,
                foregroundColor: SafirColors.primary,
                onPressed: () {
                  setState(() {
                    _cameraFollowing = true;
                  });
                },
                child: const Icon(Icons.my_location),
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
