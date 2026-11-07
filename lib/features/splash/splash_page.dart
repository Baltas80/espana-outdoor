import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const _minimumVisibleDuration = Duration(seconds: 2);

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
        systemNavigationBarColor: Color(0xFFF3F7F2),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F7F2),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFBFCF9),
                Color(0xFFF3F7F2),
                Color(0xFFE8F0E9),
              ],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 600;
                final logoSize = (constraints.maxHeight * 0.22)
                    .clamp(92.0, 156.0)
                    .toDouble();

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: compact ? 16 : 28,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Spacer(),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Semantics(
                                image: true,
                                label: 'Logotipo de España Outdoor',
                                child: SvgPicture.asset(
                                  'assets/brand/espana_outdoor_mark.svg',
                                  width: logoSize,
                                  height: logoSize,
                                  fit: BoxFit.contain,
                                  excludeFromSemantics: true,
                                ),
                              ),
                              SizedBox(height: compact ? 12 : 18),
                              Text(
                                'España Outdoor',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: TextStyle(
                                  color: OutdoorBrand.forest,
                                  fontSize: compact ? 30 : 36,
                                  height: 1.08,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.9,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: 132,
                                height: 4,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFE3322B),
                                      OutdoorBrand.sun,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'SENDERISMO · BTT · NATURALEZA · RUTAS',
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: OutdoorBrand.forest,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Semantics(
                            liveRegion: true,
                            label: 'Cargando España Outdoor',
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: OutdoorBrand.forest,
                                      backgroundColor: Color(0xFFD5E1D8),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Preparando tu próxima aventura…',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: OutdoorBrand.forest,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
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
        ),
      ),
    );
  }
}
