import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const cairoCenter = LatLng(30.0444, 31.2357);

class OpenStreetMapPreview extends StatelessWidget {
  const OpenStreetMapPreview({super.key, this.height = 235});

  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: height,
          child: FlutterMap(
            options:
                const MapOptions(initialCenter: cairoCenter, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.maa.delivery.maaCustomer',
                maxZoom: 19,
              ),
              MarkerLayer(markers: [
                Marker(
                  point: cairoCenter,
                  width: 48,
                  height: 56,
                  child: const Column(children: [
                    Icon(Icons.location_on, color: Color(0xFFFF6B4A), size: 42),
                    SizedBox(height: 2),
                  ]),
                ),
              ]),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomRight,
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors')
                ],
              ),
            ],
          ),
        ),
      );
}
