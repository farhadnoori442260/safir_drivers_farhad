import 'dart:async';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
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
  MapLibreMapController? mapController;
  StreamSubscription<Position>? _positionStream;
  Symbol? _driverSymbol;

  bool _mapStyleReady = false;
  bool _navigationStarted = false;

  void _onMapCreated(MapLibreMapController controller) {
    mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    _mapStyleReady = true;

    await _startNavigation();
    await _startLiveDriverTracking();
  }

  Future<void> _startNavigation() async {
    if (!_mapStyleReady || _navigationStarted || mapController == null) {
      return;
    }

    _navigationStarted = true;

    final controller =
        Provider.of<NavigationController>(context, listen: false);

    final points = await controller.startNavigation(
      widget.start,
      widget.destination,
      context.locale.languageCode,
    );

    if (!mounted || mapController == null || points.isEmpty) {
      _navigationStarted = false;
      return;
    }

    await mapController!.clearLines();

    await mapController!.addLine(
      LineOptions(
        geometry: points,
        lineColor: '#1B7A57',
        lineWidth: 6.0,
        lineOpacity: 0.85,
      ),
    );

    await mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: widget.start,
          zoom: 17.0,
          tilt: 45.0,
        ),
      ),
    );
  }

  Future<void> _startLiveDriverTracking() async {
    if (!_mapStyleReady || mapController == null) return;

    _positionStream?.cancel();

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen((Position position) async {
      if (!mounted || mapController == null) return;

      final rawLocation = LatLng(
        position.latitude,
        position.longitude,
      );

      final navController =
          Provider.of<NavigationController>(context, listen: false);

      navController.updateDriverPosition(
        rawLocation,
        langCode: context.locale.languageCode,
      );

      final driverLocation =
          navController.snappedDriverLocation ?? rawLocation;

      final heading = position.heading.isFinite && position.heading >= 0
          ? position.heading
          : 0.0;

      if (_driverSymbol == null) {
        _driverSymbol = await mapController!.addSymbol(
          SymbolOptions(
            geometry: driverLocation,
            iconImage: 'marker-15',
            iconSize: 2.0,
            iconColor: '#1B7A57',
            iconRotate: heading,
          ),
        );
      } else {
        await mapController!.updateSymbol(
          _driverSymbol!,
          SymbolOptions(
            geometry: driverLocation,
            iconRotate: heading,
          ),
        );
      }

      await mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: driverLocation,
            zoom: 17.5,
            bearing: heading,
            tilt: 45.0,
          ),
        ),
      );
    });
  }

  Future<void> _stopNavigation() async {
    _positionStream?.cancel();

    final controller =
        Provider.of<NavigationController>(context, listen: false);

    controller.stopNavigation();

    if (mapController != null) {
      await mapController!.clearLines();

      if (_driverSymbol != null) {
        await mapController!.removeSymbol(_driverSymbol!);
      }
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
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
            styleString: 'assets/map/style.json',
            initialCameraPosition: CameraPosition(
              target: widget.start,
              zoom: 16.0,
            ),
            myLocationEnabled: false,
            trackCameraPosition: true,
          ),
                    Consumer<NavigationController>(
            builder: (context, controller, child) {
              if (!controller.isNavigating) {
                return const SizedBox.shrink();
              }

              return const Align(
                alignment: Alignment.center,
                child: IgnorePointer(
                  child: Icon(
                    Icons.navigation,
                    color: SafirColors.primary,
                    size: 48,
                  ),
                ),
              );
            },
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
