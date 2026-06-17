import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import '../../../shared/models/floor.dart';
import '../utils/clipper.dart';
import 'components/clipped_image.dart';

class FloorPage extends StatefulWidget {
  const FloorPage({super.key});

  @override
  State<FloorPage> createState() => _FloorPageState();
}

class _FloorPageState extends State<FloorPage> {
  Floor? currentFloor;
  double x = 0;
  Future<List<Floor>> loadSvgImage({required String svgImage}) async {
    List<Floor> floors = [];
    String generalString = await rootBundle.loadString(svgImage);

    XmlDocument document = XmlDocument.parse(generalString);

    final paths = document.findAllElements('path');

    for (var element in paths) {
      String id = element.getAttribute('id').toString();
      String partPath = element.getAttribute('d').toString();
      // String name = element.getAttribute('name').toString();
      String? color = element.getAttribute('fill')?.toString();

      floors.add(Floor(id: id, path: partPath, color: color));
    }

    return floors;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder(
          future: loadSvgImage(svgImage: 'assets/floor-plan/e1.svg'),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final floors = snapshot.data as List<Floor>;
            return InteractiveViewer(
              constrained: false,
              maxScale: 5.0,
              minScale: 0.1,
              child: Stack(
                children: [
                  for (var floor in floors)
                    ClippedImage(
                      clipper: Clipper(svgPath: floor.path),
                      color: Color(int.tryParse(
                                  (floor.color ?? '').replaceAll('#', 'FF'),
                                  radix: 16) ??
                              0xffee2299)
                          .withValues(
                              alpha: currentFloor == null
                                  ? 1.0
                                  : currentFloor?.id == floor.id
                                      ? 1.0
                                      : 0.3),
                      floor: floor,
                      onFloorSelected: (floor) {
                        setState(() {
                          currentFloor = floor;
                        });
                      },
                    ),
                ],
              ),
            );
          }),
    );
  }
}
