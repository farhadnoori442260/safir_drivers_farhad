import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
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

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNavigation();
    });
  }

  Future<void> _startNavigation() async {
    final controller =
        Provider.of<NavigationController>(context, listen: false);

    final points = await controller.startNavigation(
      widget.start,
      widget.destination,
      context.locale.languageCode,
    );

    if (!mounted || mapController == null || points.isEmpty) return;

    await mapController!.clearLines();

    await mapController!.addLine(
      LineOptions(
        geometry: points,
        lineColor: '#1B7A57',
        lineWidth: 6,
        lineOpacity: 0.85,
      ),
    );
  }

  Future<void> _stopNavigation() async {
    final controller =
        Provider.of<NavigationController>(context, listen: false);

    controller.stopNavigation();

    if (mapController != null) {
      await mapController!.clearLines();
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            onMapCreated: (controller) {
              mapController = controller;
            },
            styleString: 'assets/map/style.json',
            initialCameraPosition: CameraPosition(
              target: widget.start,
              zoom: 16,
            ),
            myLocationEnabled: false,
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
