import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const _minimumDisplayDuration = Duration(milliseconds: 1200);

  Timer? _timer;
  late final Future<Uint8List> _heroBytes;

  @override
  void initState() {
    super.initState();
    _heroBytes = rootBundle
        .loadString('assets/backgrounds/splash_hero.webp.base64')
        .then((encoded) => base64Decode(encoded.trim()));
    _timer = Timer(_minimumDisplayDuration, () {
      if (mounted) context.go('/');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OutdoorBrand.darkBackground,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scale = (constraints.maxHeight / 780).clamp(0.76, 1.0).toDouble();
          final markSize = 76 * scale;

          return Stack(
            fit: StackFit.expand,
            children: [
              Semantics(
                excludeSemantics: true,
                child: FutureBuilder<Uint8List>(
                  future: _heroBytes,
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes == null) {
                      return const ColoredBox(
                        color: OutdoorBrand.darkBackground,
                      );
                    }
                    return Image.memory(
                      bytes,
                      key: const ValueKey('splash-hero-background'),
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: OutdoorBrand.darkBackground,
                      ),
                    );
                  },
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.42, 0.62, 1.0],
                        colors: [
                          Color(0x00000000),
                          Color(0x08000000),
                          Color(0x55000000),
                          Color(0xB8000000),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    10 * scale,
                    20,
                    18 * scale,
                  ),
                  child: Column(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutdoorBrandMark(size: markSize),
                          SizedBox(height: 8 * scale),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'España Outdoor',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: OutdoorBrand.forest,
                                fontSize: 34 * scale,
                                height: 1.0,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.9,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x33FFFFFF),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 3 * scale),
                          CustomPaint(
                            size: Size(168 * scale, 16 * scale),
                            painter: const _SpanishAccentPainter(),
                          ),
                          SizedBox(height: 9 * scale),
                          Text(
                            'SENDERISMO  •  BTT  •  NATURALEZA  •  RUTAS',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFF123C2B),
                              fontSize: 10.5 * scale,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.05 * scale,
                              shadows: const [
                                Shadow(
                                  color: Color(0x33FFFFFF),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 34 * scale,
                            height: 34 * scale,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: OutdoorBrand.forestLight,
                              backgroundColor: Colors.white.withValues(alpha: .72),
                            ),
                          ),
                          SizedBox(height: 14 * scale),
                          Semantics(
                            liveRegion: true,
                            label: 'Cargando España Outdoor',
                            child: Text(
                              'Cargando España Outdoor…',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15 * scale,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                shadows: const [
                                  Shadow(
                                    color: Color(0xAA000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SpanishAccentPainter extends CustomPainter {
  const _SpanishAccentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final red = Paint()
      ..color = const Color(0xFFCE2027)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final yellow = Paint()
      ..color = const Color(0xFFF2B20B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final accent = Path()
      ..moveTo(2, size.height * .72)
      ..cubicTo(
        size.width * .25,
        -size.height * .15,
        size.width * .64,
        size.height * 1.05,
        size.width - 2,
        size.height * .20,
      );
    canvas.drawPath(accent, red);

    final underline = Path()
      ..moveTo(8, size.height * .88)
      ..cubicTo(
        size.width * .30,
        size.height * .15,
        size.width * .62,
        size.height * 1.08,
        size.width - 8,
        size.height * .43,
      );
    canvas.drawPath(underline, yellow);
  }

  @override
  bool shouldRepaint(covariant _SpanishAccentPainter oldDelegate) => false;
}
