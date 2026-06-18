import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geodesy/geodesy.dart';
import 'package:geolocator/geolocator.dart';

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

  void _loadGeoJson() async {
    final String data = await rootBundle.loadString('assets/json/koe_geo.json');
    final geojson = json.decode(data);

    for (var polygon in geojson['features']) {
      List<LatLng> points = [];
      for (var point in polygon['geometry']['coordinates'][0]) {
        points.add(LatLng(point[1], point[0]));
      }
      final myPolygon = Polygon(
        // label: 'KOE E1 L1',
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

    Future.delayed(Durations.long1, () {
      _loadGeoJson();
    });
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
                    const LatLng(3.25320988279517, 101.73129791620775),
                initialZoom: 18,
                onTap: (tapPosition, point) {
                  final res = GeoPoints.isGeoPointInPolygon(
                      point, polygons.first.points);
                  // TODO: I hardcoded the level here (.first)
                  if (res) {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const LevelPage(
                            // initialGoid: 'E1L1',
                            )));
                  }
                },
                onMapReady: () async {
                  final myPos = await Geolocator.getCurrentPosition(
                      locationSettings: const LocationSettings(
                          accuracy: LocationAccuracy.best));

                  mapController.move(
                      LatLng(myPos.latitude, myPos.longitude), 18);
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
                          )),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8.0,
                left: 8.0,
                right: 8.0),
            child: SearchAnchor(
                builder: (BuildContext context, SearchController controller) {
              return SearchBar(
                // amende do ni serabut je MaterialStateProperty lah guna je la
                // colors tu
                surfaceTintColor: WidgetStateProperty.all<Color>(
                    Theme.of(context).colorScheme.surface),
                backgroundColor: WidgetStateProperty.all<Color>(
                    Theme.of(context).colorScheme.surface),
                overlayColor: WidgetStateProperty.all<Color>(
                    Theme.of(context).colorScheme.surface),
                controller: controller,
                padding: const WidgetStatePropertyAll<EdgeInsets>(
                    EdgeInsets.symmetric(horizontal: 16.0)),
                onTap: () {
                  controller.openView();
                },

                onSubmitted: (value) {
                  print('Selected value: $value');
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => FloorMap(
                            initialGoid: value,
                            level: 1,
                          )));
                },
                onChanged: (_) {
                  controller.openView();
                },
                leading: const Icon(Icons.search),
              );
            }, suggestionsBuilder:
                    (BuildContext context, SearchController controller) async {
              final jsonData =
                  await rootBundle.loadString('assets/json/floor.json');
              FloorMetadata floorMetadata =
                  FloorMetadata.fromJson(jsonDecode(jsonData));

              return floorMetadata.data.e1.l1!.map((venue) => ListTile(
                    title: Text(venue.name!),
                    subtitle: const Text('KOE E1 L1'),
                    onTap: () {
                      controller.closeView(venue.id);
                    },
                  ));
            }),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          setState(() => isDetectingLocation = true);
          final myPos = await Geolocator.getCurrentPosition(
              locationSettings:
                  const LocationSettings(accuracy: LocationAccuracy.best));

          mapController.move(LatLng(myPos.latitude, myPos.longitude), 19);

          setState(() {
            isDetectingLocation = false;
            currentLocation = LatLng(myPos.latitude, myPos.longitude);
          });
        },
        // child: Icon(Icons.my_location_outlined),
        child: isDetectingLocation
            ? const BlinkingGps()
            : const Icon(Icons.gps_fixed),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    mapController.dispose();
  }
}
