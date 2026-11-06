import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';
import '../../app/eo_components.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const _minimumVisibleDuration = Duration(milliseconds: 1200);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_minimumVisibleDuration, () {
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: EOColors.night,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: EOColors.night,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: Image(
                image: AssetImage('assets/images/routes/picos_de_europa.jpg'),
                fit: BoxFit.cover,
                alignment: Alignment(-1, 0),
                filterQuality: FilterQuality.high,
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x0806171A),
                      Color(0x0006171A),
                      Color(0x2606171A),
                      Color(0xE606171A),
                    ],
                    stops: [0, 0.43, 0.68, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final markSize = (constraints.maxHeight * 0.12)
                      .clamp(72.0, 108.0)
                      .toDouble();
                  final compact = constraints.maxHeight < 640;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      constraints.maxHeight * 0.025,
                      20,
                      constraints.maxHeight * 0.055,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutdoorBrandMark(size: markSize),
                                SizedBox(height: compact ? 8 : 12),
                                const Text(
                                  'España Outdoor',
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF103B2D),
                                    fontSize: 32,
                                    height: 1.08,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.8,
                                    shadows: [
                                      Shadow(
                                        color: Color(0x55FFFFFF),
                                        blurRadius: 8,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  width: 156,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFE3322B),
                                        Color(0xFFF2A11A),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'SENDERISMO · BTT · NATURALEZA · RUTAS',
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: Color(0xFF173B30),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.65,
                                      shadows: [
                                        Shadow(
                                          color: Color(0x66FFFFFF),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Semantics(
                              liveRegion: true,
                              label: 'Cargando España Outdoor',
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3.5,
                                      color: OutdoorBrand.forestLight,
                                      backgroundColor: Color(0x88FFFFFF),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Cargando España Outdoor…',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.75,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
