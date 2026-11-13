import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'geometry.dart';
import 'scan_session.dart';

/// Lets the user draw a rectangle around a board. Pops with a [Quad] in page
/// pixels, or `null`.
class RegionPickerScreen extends StatefulWidget {
  const RegionPickerScreen({super.key, required this.page});

  final ScanPage page;

  @override
  State<RegionPickerScreen> createState() => _RegionPickerScreenState();
}

class _RegionPickerScreenState extends State<RegionPickerScreen> {
  static const double _minSide = 24;

  Offset? _start;
  Offset? _end;
  double _scale = 1;

  Rect? get _rect {
    final a = _start;
    final b = _end;
    if (a == null || b == null) return null;
    return Rect.fromPoints(a, b);
  }

  bool get _usable {
    final r = _rect;
    return r != null && r.width >= _minSide && r.height >= _minSide;
  }

  void _done() {
    final r = _rect;
    if (r == null) return;
    Navigator.of(context).pop(
      Quad.fromRect(r.left / _scale, r.top / _scale, r.right / _scale, r.bottom / _scale),
    );
  }

  Offset _clamp(Offset p, Size size) => Offset(
        p.dx.clamp(0.0, size.width),
        p.dy.clamp(0.0, size.height),
      );

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Select the board')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Drag a box around the diagram.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _scale = math.min(
                    constraints.maxWidth / page.width,
                    constraints.maxHeight / page.height,
                  );
                  final size = Size(page.width * _scale, page.height * _scale);
                  return Center(
                    child: SizedBox.fromSize(
                      size: size,
                      child: GestureDetector(
                        onPanStart: (d) => setState(() {
                          _start = _clamp(d.localPosition, size);
                          _end = _start;
                        }),
                        onPanUpdate: (d) => setState(() {
                          _end = _clamp(d.localPosition, size);
                        }),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(page.jpeg, fit: BoxFit.fill, gaplessPlayback: true),
                            CustomPaint(
                              painter: _RectPainter(_rect, theme.colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _usable ? _done : null,
                  child: const Text('Read this area'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RectPainter extends CustomPainter {
  _RectPainter(this.rect, this.color);

  final Rect? rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect;
    if (r == null) return;
    canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawRect(
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RectPainter old) => old.rect != rect || old.color != color;
}

/// Lets the user drag the four corners of a board. Pops with the new [Quad]
/// in page pixels, or `null`.
class QuadEditorScreen extends StatefulWidget {
  const QuadEditorScreen({super.key, required this.page, required this.quad});

  final ScanPage page;
  final Quad quad;

  @override
  State<QuadEditorScreen> createState() => _QuadEditorScreenState();
}

class _QuadEditorScreenState extends State<QuadEditorScreen> {
  static const double _handle = 44;

  late Quad _quad = widget.quad;
  late final Rect _region = _regionFor(widget.quad);

  Rect _regionFor(Quad quad) {
    final pad = math.max(40.0, 0.35 * math.max(quad.width, quad.height));
    final box = Rect.fromLTRB(quad.minX, quad.minY, quad.maxX, quad.maxY).inflate(pad);
    return box.intersect(
      Rect.fromLTWH(0, 0, widget.page.width.toDouble(), widget.page.height.toDouble()),
    );
  }

  void _move(int index, Offset delta, double scale) {
    final p = _quad.points[index];
    setState(() {
      _quad = _quad.withPoint(
        index,
        Pt(
          (p.x + delta.dx / scale).clamp(_region.left, _region.right),
          (p.y + delta.dy / scale).clamp(_region.top, _region.bottom),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Adjust the corners')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Drag each dot to a corner of the 8 by 8 squares.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = math.min(
                    (constraints.maxWidth - _handle) / _region.width,
                    (constraints.maxHeight - _handle) / _region.height,
                  );
                  final size = Size(_region.width * scale, _region.height * scale);
                  return Center(
                    child: SizedBox.fromSize(
                      size: size,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: ClipRect(
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: -_region.left * scale,
                                    top: -_region.top * scale,
                                    width: page.width * scale,
                                    height: page.height * scale,
                                    child: Image.memory(
                                      page.jpeg,
                                      fit: BoxFit.fill,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _QuadPainter(
                                        quad: _quad,
                                        origin: _region.topLeft,
                                        scale: scale,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          for (var i = 0; i < 4; i++)
                            Positioned(
                              left: (_quad.points[i].x - _region.left) * scale - _handle / 2,
                              top: (_quad.points[i].y - _region.top) * scale - _handle / 2,
                              width: _handle,
                              height: _handle,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (d) => _move(i, d.delta, scale),
                                child: Center(
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: theme.colorScheme.primary.withValues(alpha: 0.85),
                                      border: Border.all(
                                        color: theme.colorScheme.onPrimary,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_quad),
                    child: const Text('Read the board again'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({
    required this.quad,
    required this.origin,
    required this.scale,
    required this.color,
  });

  final Quad quad;
  final Offset origin;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final p = quad.points[i];
      final o = Offset((p.x - origin.dx) * scale, (p.y - origin.dy) * scale);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.quad != quad || old.scale != scale || old.color != color;
}
