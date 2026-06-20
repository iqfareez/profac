import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geodesy/geodesy.dart';

import '../../../shared/constants.dart';
import '../../../shared/models/floor_metadata.dart';
import '../../building/views/floor_map.dart';
import '../../building/views/level_page.dart';
import 'components/blinking_gps.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final mapController = MapController();
  bool isDetectingLocation = false;
  LatLng? currentLocation;
  List<Polygon> polygons = [];

  void _openFloorMap(BuildContext context, String roomId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FloorMap(
          initialGoid: roomId,
          level: 1,
        ),
      ),
    );
  }

  void _loadGeoJson() async {
    final String data = await rootBundle.loadString('assets/json/koe_geo.json');
    final geojson = json.decode(data);

    for (var polygon in geojson['features']) {
      List<LatLng> points = [];
      for (var point in polygon['geometry']['coordinates'][0]) {
        points.add(LatLng(point[1], point[0]));
      }
      final myPolygon = Polygon(
        points: points,
        color: Colors.pink.withAlpha(70),
      );
      polygons.add(myPolygon);
    }

    setState(() {});
  }

  @override
  void initState() {
    super.initState();

    Future.delayed(Durations.long1, _loadGeoJson);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter:
                    const LatLng(3.2531050169620577, 101.73180045891706),
                initialZoom: 18,
                onTap: (tapPosition, point) {
                  final res = GeoPoints.isGeoPointInPolygon(
                    point,
                    polygons.first.points,
                  );
                  if (res) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const LevelPage(),
                      ),
                    );
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.iqfareez.cari_venue',
                ),
                PolygonLayer(polygons: polygons),
                MarkerLayer(
                  markers: [
                    if (currentLocation != null)
                      Marker(
                        point: currentLocation!,
                        width: 80,
                        height: 80,
                        child: Icon(
                          Icons.person_pin_circle_rounded,
                          size: 80,
                          color: Colors.blue.shade700,
                        ),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
            ),
            child: SearchAnchor(
              builder: (BuildContext context, SearchController controller) {
                return SearchBar(
                  surfaceTintColor: WidgetStateProperty.all<Color>(
                    Theme.of(context).colorScheme.surface,
                  ),
                  backgroundColor: WidgetStateProperty.all<Color>(
                    Theme.of(context).colorScheme.surface,
                  ),
                  overlayColor: WidgetStateProperty.all<Color>(
                    Theme.of(context).colorScheme.surface,
                  ),
                  controller: controller,
                  padding: const WidgetStatePropertyAll<EdgeInsets>(
                    EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onTap: controller.openView,
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      _openFloorMap(context, value);
                    }
                  },
                  onChanged: (_) {
                    controller.openView();
                  },
                  leading: const Icon(Icons.search),
                );
              },
              suggestionsBuilder:
                  (BuildContext context, SearchController controller) async {
                final jsonData =
                    await rootBundle.loadString('assets/json/floor.json');
                final floorMetadata =
                    FloorMetadata.fromJson(jsonDecode(jsonData));

                return floorMetadata.data.e1.l1!.map((venue) {
                  final roomId = venue.id;
                  return ListTile(
                    title: Text(venue.name!),
                    subtitle: const Text('KOE E1 L1'),
                    onTap: roomId == null
                        ? null
                        : () {
                            controller.closeView(roomId);
                            _openFloorMap(context, roomId);
                          },
                  );
                });
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          setState(() => isDetectingLocation = true);

          mapController.move(kKoeComplexLatLng, 19);

          setState(() {
            isDetectingLocation = false;
            currentLocation = kKoeComplexLatLng;
          });
        },
        child: isDetectingLocation
            ? const BlinkingGps()
            : const Icon(Icons.gps_fixed),
      ),
    );
  }

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }
}
