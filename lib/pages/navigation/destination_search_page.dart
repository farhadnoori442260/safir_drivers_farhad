import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../models/place_search_result.dart';
import '../../utils/app_colors.dart';
import 'navigation_page.dart';
import '../../widgets/navigation/destination_search_sheet.dart';

class DestinationSearchPage extends StatefulWidget {
  final LatLng driverLocation;

  const DestinationSearchPage({
    super.key,
    required this.driverLocation,
  });

  @override
  State<DestinationSearchPage> createState() =>
      _DestinationSearchPageState();
}

class _DestinationSearchPageState extends State<DestinationSearchPage> {
  static const String _destinationPinImage = 'safir-destination-select-pin';

  MapLibreMapController? _mapController;
  Symbol? _destinationSymbol;

  PlaceSearchResult? _selectedPlace;

  bool _isStyleLoaded = false;
  bool _isDestinationImageAdded = false;

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    _isStyleLoaded = true;

    await _addDestinationPinImage();
    await _showSelectedDestinationOnMap();
  }

  Future<void> _addDestinationPinImage() async {
    if (_mapController == null || _isDestinationImageAdded) return;

    const width = 100;
    const height = 124;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(width.toDouble(), height.toDouble());

    _drawDestinationPin(canvas, size);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);

    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (bytes == null || _mapController == null) return;

    await _mapController!.addImage(
      _destinationPinImage,
      bytes.buffer.asUint8List(),
    );

    _isDestinationImageAdded = true;
  }

  void _drawDestinationPin(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final pinBottom = size.height - 7.0;

    final path = Path()
      ..moveTo(centerX, pinBottom)
      ..cubicTo(12, size.height - 43, 10, 23, centerX, 8)
      ..cubicTo(
        size.width - 10,
        23,
        size.width - 12,
        size.height - 43,
        centerX,
        pinBottom,
      )
      ..close();

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawPath(path.shift(const Offset(0, 4)), shadowPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, borderPaint);

    final fillPaint = Paint()..color = const Color(0xFFE84C4C);

    canvas.drawPath(path, fillPaint);

    canvas.drawCircle(
      Offset(centerX, 43),
      14,
      Paint()..color = Colors.white,
    );

    canvas.drawCircle(
      Offset(centerX, 43),
      7,
      Paint()..color = const Color(0xFFE84C4C),
    );
  }

  Future<void> _onPlaceSelected(PlaceSearchResult place) async {
    setState(() {
      _selectedPlace = place;
    });

    await _showSelectedDestinationOnMap();
  }

  Future<void> _showSelectedDestinationOnMap() async {
    if (!_isStyleLoaded ||
        !_isDestinationImageAdded ||
        _mapController == null ||
        _selectedPlace == null) {
      return;
    }

    final destination = LatLng(
      _selectedPlace!.latitude,
      _selectedPlace!.longitude,
    );

    final options = SymbolOptions(
      geometry: destination,
      iconImage: _destinationPinImage,
      iconSize: 0.70,
    );

    if (_destinationSymbol == null) {
      _destinationSymbol = await _mapController!.addSymbol(options);

      await _mapController!.setSymbolIconAllowOverlap(true);
      await _mapController!.setSymbolIconIgnorePlacement(true);
    } else {
      await _mapController!.updateSymbol(
        _destinationSymbol!,
        options,
      );
    }

    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: destination,
          zoom: 16.5,
        ),
      ),
      duration: const Duration(milliseconds: 550),
    );
  }

  void _confirmDestination() {
    if (_selectedPlace == null) return;

    final destination = LatLng(
      _selectedPlace!.latitude,
      _selectedPlace!.longitude,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NavigationPage(
          start: widget.driverLocation,
          destination: destination,
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_mapController != null && _destinationSymbol != null) {
      _mapController!.removeSymbol(_destinationSymbol!);
    }

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
            initialCameraPosition: CameraPosition(
              target: widget.driverLocation,
              zoom: 15.5,
            ),
            styleString: 'assets/map/style.json',
            myLocationEnabled: false,
            trackCameraPosition: true,
          ),
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Material(
                color: Colors.white,
                elevation: 5,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'بازگشت',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: SafirColors.primary,
                  ),
                ),
              ),
            ),
          ),
          DestinationSearchSheet(
            selectedPlace: _selectedPlace,
            onPlaceSelected: _onPlaceSelected,
            onConfirmDestination: _confirmDestination,
          ),
        ],
      ),
    );
  }
}
