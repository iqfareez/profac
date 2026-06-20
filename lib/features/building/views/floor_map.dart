import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../home/views/home_page.dart';
import '../models/floor_data.dart';
import '../models/room.dart';

/// Credit to https://gist.github.com/pskink/afd4f20a40ae7756555877ec030daa46 for this code
/// that works even though it is scary
class FloorMap extends StatefulWidget {
  const FloorMap({super.key, this.initialGoid, required this.level});

  /// Pass this ID so that it can move to it when this pag is loaded
  final String? initialGoid;

  final int level;

  @override
  State<FloorMap> createState() => _FloorMapState();
}

class _FloorMapState extends State<FloorMap> with TickerProviderStateMixin {
  late final actrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
  FloorData? worldData;
  TransformationController? tctrl;
  late Animation<Matrix4> animation;
  late ExtendedViewport extendedViewport;
  bool _didRunInitialZoom = false;

  @override
  void initState() {
    super.initState();
    actrl.addListener(() => tctrl?.value = animation.value);
    _parse().then((value) {
      setState(() => worldData = value);
    });
  }

  Matrix4 rectToRect(
    Rect src,
    Rect dst, {
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  }) {
    FittedSizes fs = applyBoxFit(fit, src.size, dst.size);
    double scaleX = fs.destination.width / fs.source.width;
    double scaleY = fs.destination.height / fs.source.height;
    Size fittedSrc = Size(src.width * scaleX, src.height * scaleY);
    Rect out = alignment.inscribe(fittedSrc, dst);

    return Matrix4.identity()
      ..translateByVector3(Vector3(out.left, out.top, 0))
      ..scaleByVector3(Vector3(scaleX, scaleY, 1))
      ..translateByVector3(Vector3(-src.left, -src.top, 0));
  }

  Matrix4 _zoomTo(String id, Size size) {
    return rectToRect(
      worldData!.rooms[id]!.rect,
      Offset.zero & size,
      fit: BoxFit.contain,
    );
  }

  void _animateToRoom(String id, Size size, {Curve curve = Curves.easeInOut}) {
    final room = worldData?.rooms[id];
    if (room == null || tctrl == null || !mounted) return;

    final begin = tctrl!.value;
    final end = _zoomTo(id, size);
    if (begin == end) return;

    animation = Matrix4Tween(
      begin: begin,
      end: end,
    ).chain(CurveTween(curve: curve)).animate(actrl);
    actrl.forward(from: 0);
  }

  void _scheduleInitialZoom(Size size) {
    if (_didRunInitialZoom || widget.initialGoid == null) return;
    _didRunInitialZoom = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animateToRoom(
        widget.initialGoid!,
        size,
        curve: Curves.easeInExpo,
      );
    });
  }

  TransformationController _initController(Size size) {
    final matrix = rectToRect(Offset.zero & worldData!.size, Offset.zero & size,
        fit: BoxFit.cover);
    final ctrl = TransformationController(matrix);
    extendedViewport = ExtendedViewport(
      ctrl: ctrl,
      cacheFactor: 1.75,
    );
    return ctrl;
  }

  @override
  Widget build(BuildContext context) {
    if (worldData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: _InkFactory(),
      ),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.adaptive.arrow_back),
            onPressed: () {
              // HACK: When I go back, I got this vague error '!_debugDisposed': is not true.
              // DOn't have time to debug this, so here is quick, dirty and horrible solution
              Navigator.of(context).push(MaterialPageRoute(builder: (_) {
                return const Home();
              }));
            },
          ),
          title: Text('E1: Level ${widget.level}'),
        ),
        body: LayoutBuilder(builder: (context, constraints) {
          tctrl ??= _initController(constraints.biggest);
          extendedViewport.size = constraints.biggest;
          _scheduleInitialZoom(constraints.biggest);
          return ColoredBox(
            color: Colors.blueGrey.shade50,
            child: InteractiveViewer(
              constrained: false,
              transformationController: tctrl,
              minScale: .2,
              maxScale: 50,
              child: Flow(
                delegate: FloorMapDelegate(worldData!, extendedViewport),
                children: worldData!.rooms.values
                    .map((country) =>
                        _countryBuilder(country, constraints.biggest))
                    .toList(),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _countryBuilder(Room country, Size size) {
    final shape = CountryBorder(country.path.shift(-country.rect.topLeft));
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        color: Colors.purple.shade100,
        // gradient: country.gradient,
        // shadows: const [
        //   BoxShadow(blurRadius: 0.5),
        //   BoxShadow(blurRadius: 0.5, offset: Offset(0.5, 0.5)),
        // ],
      ),
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        shape: shape,
        child: InkWell(
          highlightColor: Colors.transparent,
          onTap: () {
            _animateToRoom(country.id, size);
          },
          child: Center(
              child: Text(
            country.id,
            textScaler: const TextScaler.linear(.5),
          )),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    actrl.dispose();
    tctrl?.dispose();
  }

  Future<FloorData> _parse() async {
    // get it from https://mapsvg.com/static/maps/geo-calibrated/world.svg
    // more maps: https://mapsvg.com/maps
    final xml = await rootBundle
        .loadString('assets/floor-plan/E1/L${widget.level}.svg');

    final doc = XmlDocument.parse(xml);
    final w = double.parse(doc.rootElement.getAttribute('width')!);
    final h = double.parse(doc.rootElement.getAttribute('height')!);

    List<Color> colors(double h) {
      return [
        HSVColor.fromAHSV(1, h * 360, 1, 0.9).toColor(),
        HSVColor.fromAHSV(1, h * 360, 1, 0.3).toColor(),
      ];
    }

    const padding = EdgeInsets.all(40);
    final allRooms = doc.rootElement.findElements('path');
    final numCountries = allRooms.length;
    final countries = allRooms.mapIndexed((i, country) => Room(
          path: parseSvgPathData(country.getAttribute('d')!)
              .shift(padding.topLeft),
          id: country.getAttribute('id') ?? 'id_$i ???',
          title: country.getAttribute('title') ?? 'title_$i ???',
          gradient: LinearGradient(
            colors: colors(i / numCountries),
            stops: const [0.2, 1],
          ),
          seqNo: i,
        ));
    return FloorData(
      size: Size(w + padding.horizontal, h + padding.vertical),
      rooms: {
        for (final country in countries) country.id: country,
      },
    );
  }
}

class FloorMapDelegate extends FlowDelegate {
  FloorMapDelegate(this.worldData, this.extendedViewport)
      : super(repaint: extendedViewport);

  final FloorData worldData;
  final ValueNotifier<Rect> extendedViewport;

  @override
  void paintChildren(FlowPaintingContext context) {
    final filteredRooms = worldData.rooms.values
        .where((country) => country.rect.overlaps(extendedViewport.value));
    for (final room in filteredRooms) {
      final offset = room.rect.topLeft;
      context.paintChild(room.seqNo,
          transform: Matrix4.translationValues(offset.dx, offset.dy, 0));
    }
  }

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    // print('getConstraintsForChild $i');
    final country = worldData.rooms.values.elementAt(i);
    return BoxConstraints.tight(country.rect.size);
  }

  @override
  Size getSize(BoxConstraints constraints) => worldData.size;

  @override
  bool shouldRepaint(covariant FlowDelegate oldDelegate) => false;
}

class ExtendedViewport extends ValueNotifier<Rect> {
  ExtendedViewport({
    required this.ctrl,
    required this.cacheFactor,
  }) : super(Rect.largest) {
    ctrl.addListener(_buildViewport);
  }

  final TransformationController ctrl;
  final double cacheFactor;
  Size _size = Size.zero;
  set size(Size size) {
    if (size != _size) {
      _size = size;
    }
  }

  Rect innerRect = Rect.zero;
  double prevScale = 0;

  void _buildViewport() {
    assert(_size != Size.zero);
    final offset = ctrl.toScene(_size.center(Offset.zero));
    final scale = ctrl.value.getMaxScaleOnAxis();

    if (!innerRect.contains(offset) || scale != prevScale) {
      prevScale = scale;
      value = Rect.fromCenter(
        center: offset,
        width: _size.width * cacheFactor / scale,
        height: _size.height * cacheFactor / scale,
      );
      // print('value: $value');
      innerRect = EdgeInsets.symmetric(
        horizontal: _size.width * 0.5 / scale,
        vertical: _size.height * 0.5 / scale,
      ).deflateRect(value);
    }
  }
}

class CountryBorder extends ShapeBorder {
  const CountryBorder(this.path);

  final Path path;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return rect.topLeft == Offset.zero ? path : path.shift(rect.topLeft);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas
      ..save()
      ..clipPath(path)
      ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.25
            ..color = Colors.white38)
      ..restore();
  }

  @override
  ShapeBorder scale(double t) => this;
}

const Duration _kDuration = Duration(milliseconds: 650);

class _InkFactory extends InteractiveInkFeatureFactory {
  @override
  InteractiveInkFeature create(
      {required MaterialInkController controller,
      required RenderBox referenceBox,
      required Offset position,
      required Color color,
      required TextDirection textDirection,
      bool containedInkWell = false,
      RectCallback? rectCallback,
      BorderRadius? borderRadius,
      ShapeBorder? customBorder,
      double? radius,
      VoidCallback? onRemoved}) {
    return _InkFeature(
        controller: controller,
        referenceBox: referenceBox,
        color: color,
        position: position);
  }
}

class _InkFeature extends InteractiveInkFeature {
  _InkFeature(
      {required MaterialInkController controller,
      required super.referenceBox,
      required super.color,
      required this.position})
      : super(controller: controller) {
    _controller =
        AnimationController(duration: _kDuration, vsync: controller.vsync)
          ..addListener(controller.markNeedsPaint)
          ..forward();
    controller.addInkFeature(this);
  }

  static const gradient = LinearGradient(
    colors: [Colors.amber, Colors.deepOrange],
  );

  late AnimationController _controller;
  final Offset position;

  @override
  void confirm() => _controller.reverse().then((value) => dispose());

  @override
  void cancel() => _controller.reverse().then((value) => dispose());

  @override
  void dispose() {
    // print('dispose');
    super.dispose();
    _controller.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final scale = referenceBox.getTransformTo(null).getMaxScaleOnAxis();
    final t = Curves.easeInOut.transform(_controller.value);
    final rect = Offset.zero & referenceBox.size;
    final side = 2 * rect.bottomRight.distance;

    final paint = Paint()
      ..color = Color.fromARGB(
          lerpDouble(100, 255, _controller.value)!.toInt(), 0, 0, 0)
      ..shader = gradient.createShader(rect);
    final matrix = composeMatrixFromOffsets(
      anchor: position,
      translate: position,
      rotation: pi * .75 * t,
    );
    final hFactor = const Cubic(1, 0, 1, 1).transform(t);
    final path = Path()
      ..addOval(
        Rect.fromCenter(
            center: position,
            width: side * _controller.value,
            height: (48 / scale + side * hFactor) * _controller.value),
      );
    canvas
      ..save()
      ..transform(matrix.storage)
      ..drawPath(path, paint)
      ..restore();
  }
}

Matrix4 composeMatrixFromOffsets({
  double scale = 1,
  double rotation = 0,
  Offset translate = Offset.zero,
  Offset anchor = Offset.zero,
}) {
  final double c = cos(rotation) * scale;
  final double s = sin(rotation) * scale;
  final double dx = translate.dx - c * anchor.dx + s * anchor.dy;
  final double dy = translate.dy - s * anchor.dx - c * anchor.dy;
  return Matrix4(c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);
}
