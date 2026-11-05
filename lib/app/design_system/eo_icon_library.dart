import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Official España Outdoor vector icon set. All assets use a 24x24 grid,
/// consistent 1.8px strokes and transparent backgrounds.
enum EOIconName {
  compass,
  map,
  route,
  offline,
  pets,
  wildlife,
  nature,
  safety,
  weather,
  cycling,
  hiking,
  elevation,
  gpx,
  rescue,
  profile,
}

class EOIcon extends StatelessWidget {
  const EOIcon(
    this.name, {
    this.size = 24,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final EOIconName name;
  final double size;
  final Color? color;
  final String? semanticLabel;

  String get asset => 'assets/visuals/icons/library/${name.name}.svg';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
      semanticsLabel: semanticLabel ?? name.name,
    );
  }
}
