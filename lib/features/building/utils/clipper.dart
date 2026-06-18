import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class Clipper extends CustomClipper<Path> {
  Clipper({
    required this.svgPath,
  });

  String svgPath;

  @override
  Path getClip(Size size) {
    var path = parseSvgPathData(svgPath);
    final Matrix4 matrix4 = Matrix4.identity();

    matrix4.scaleByVector3(Vector3(1.1, 1.1, 1.0));

    return path.transform(matrix4.storage).shift(const Offset(-220, 0));
  }

  @override
  bool shouldReclip(CustomClipper oldClipper) {
    return false;
  }
}
