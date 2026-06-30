import 'dart:io';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;

import '../config/app_config.dart';

/// True when Apple Maps should render under flutter_map course overlays.
bool useAppleMapsBackdrop(MapBackground mapBackground) =>
    !kIsWeb && Platform.isIOS && mapBackground == MapBackground.appleMaps;

/// Syncs MapKit camera to match a [MapController] from flutter_map.
class AppleMapsBackdrop extends StatefulWidget {
  const AppleMapsBackdrop({
    super.key,
    required this.mapController,
    this.mapType = apple.MapType.hybrid,
  });

  final MapController mapController;
  final apple.MapType mapType;

  @override
  State<AppleMapsBackdrop> createState() => AppleMapsBackdropState();
}

class AppleMapsBackdropState extends State<AppleMapsBackdrop> {
  apple.AppleMapController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => syncFromFlutterMap());
  }

  void syncFromFlutterMap() {
    final controller = _controller;
    if (controller == null) return;

    final camera = widget.mapController.camera;
    if (camera.nonRotatedSize == MapCamera.kImpossibleSize) return;

    controller.moveCamera(
      apple.CameraUpdate.newCameraPosition(_appleCamera(camera)),
    );
  }

  apple.CameraPosition _appleCamera(MapCamera camera) {
    final center = camera.center;
    return apple.CameraPosition(
      target: apple.LatLng(center.latitude, center.longitude),
      zoom: camera.zoom,
      heading: _appleHeadingFromFlutterRotation(camera.rotation),
    );
  }

  static double _appleHeadingFromFlutterRotation(double flutterRotation) {
    return (360 - flutterRotation) % 360;
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.mapController.camera;
    final initialCenter = initial.nonRotatedSize == MapCamera.kImpossibleSize
        ? latlong.LatLng(
            AppConfig.defaultCenter[0],
            AppConfig.defaultCenter[1],
          )
        : initial.center;

    return apple.AppleMap(
      mapType: widget.mapType,
      compassEnabled: false,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      rotateGesturesEnabled: false,
      scrollGesturesEnabled: false,
      zoomGesturesEnabled: false,
      pitchGesturesEnabled: false,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      initialCameraPosition: apple.CameraPosition(
        target: apple.LatLng(initialCenter.latitude, initialCenter.longitude),
        zoom: initial.zoom == 0 ? 15 : initial.zoom,
        heading: _appleHeadingFromFlutterRotation(initial.rotation),
      ),
      onMapCreated: (controller) {
        _controller = controller;
        syncFromFlutterMap();
      },
    );
  }
}
