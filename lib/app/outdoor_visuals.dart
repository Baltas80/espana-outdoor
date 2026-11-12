import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class OutdoorVisualHero extends StatelessWidget {
  const OutdoorVisualHero({
    super.key,
    required this.asset,
    required this.title,
    this.subtitle,
  });

  final String asset;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 1.7,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _VisualAsset(asset: asset, semanticsLabel: title),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Theme.of(context).colorScheme.scrim.withValues(alpha: .78),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisualAsset extends StatelessWidget {
  const _VisualAsset({required this.asset, required this.semanticsLabel});

  final String asset;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (asset.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        fit: BoxFit.cover,
        semanticsLabel: semanticsLabel,
      );
    }
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticsLabel,
    );
  }
}

class OutdoorAssetIcon extends StatelessWidget {
  const OutdoorAssetIcon({
    super.key,
    required this.asset,
    this.size = 44,
  });

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconColor =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    final image = asset.toLowerCase().endsWith('.svg')
        ? SvgPicture.asset(
            asset,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          )
        : Image.asset(
            asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            color: iconColor,
            colorBlendMode: BlendMode.srcIn,
            semanticLabel: asset.split('/').last,
          );
    return SizedBox(width: size, height: size, child: image);
  }
}
