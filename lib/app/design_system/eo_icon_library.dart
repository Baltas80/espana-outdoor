import 'package:flutter/material.dart';

/// Premium España Outdoor icon library. Every icon resolves to an independent
/// raster asset generated from the approved artwork.
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
  wildfire,
  contacts,
  coverage,
  photos,
  history,
  achievements,
  plans,
  settings,
  astronomy,
  poi,
  alerts,
  backtrack,
}

class EOIcon extends StatelessWidget {
  const EOIcon(
    this.name, {
    this.size = 24,
    this.semanticLabel,
    super.key,
  });

  final EOIconName name;
  final double size;
  final String? semanticLabel;

  String get asset =>
      'assets/visuals/icons/library/premium/${name.name}.webp';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel ?? name.name,
    );
  }
}
