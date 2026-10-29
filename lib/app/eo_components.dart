import 'dart:ui';

import 'package:flutter/material.dart';

/// España Outdoor V1 component system.
///
/// These components are the single UI vocabulary for the premium visual
/// language. Feature screens should compose these widgets rather than define
/// their own colors, radii, spacing or interaction states.
abstract final class EOColors {
  static const night = Color(0xFF06161A);
  static const surface = Color(0xFF0B2024);
  static const surfaceElevated = Color(0xFF102B2F);
  static const green = Color(0xFF16A34A);
  static const greenPressed = Color(0xFF087A36);
  static const greenSoft = Color(0xFF1F7A45);
  static const white = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFD6E0E1);
  static const textTertiary = Color(0xFF8FA3A6);
  static const border = Color(0xFF294347);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const blue = Color(0xFF3B82F6);
}

abstract final class EOSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 48.0;
}

abstract final class EORadii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
}

abstract final class EOTextStyles {
  static const hero = TextStyle(
    color: EOColors.white,
    fontSize: 32,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );
  static const title = TextStyle(
    color: EOColors.white,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w700,
  );
  static const cardTitle = TextStyle(
    color: EOColors.white,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );
  static const body = TextStyle(
    color: EOColors.white,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );
  static const secondary = TextStyle(
    color: EOColors.textSecondary,
    fontSize: 12,
    height: 1.35,
  );
  static const label = TextStyle(
    color: EOColors.white,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w500,
  );
}

class EOButton extends StatelessWidget {
  const EOButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.danger = false,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? EOColors.red
        : secondary
            ? EOColors.surfaceElevated
            : EOColors.green;
    final foreground = EOColors.white;
    final border = secondary ? EOColors.border : Colors.transparent;

    return SizedBox(
      height: 48,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(EORadii.md),
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(EORadii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: EOSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(EORadii.md),
              border: Border.all(color: border),
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: EOColors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 18, color: foreground),
                          const SizedBox(width: EOSpacing.sm),
                        ],
                        Text(
                          label,
                          style: EOTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class EOIconButton extends StatelessWidget {
  const EOIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.selected = false,
    this.danger = false,
    this.size = 48,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final bool danger;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: danger
            ? EOColors.red
            : selected
                ? EOColors.green
                : EOColors.surface.withValues(alpha: .94),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Icon(
            icon,
            size: 22,
            color: EOColors.white,
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class EOAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EOAppBar({
    required this.title,
    this.leading,
    this.actions = const [],
    this.transparent = false,
    super.key,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final bool transparent;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => AppBar(
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        leading: leading,
        titleSpacing: leading == null ? EOSpacing.lg : 0,
        title: Text(title, style: EOTextStyles.title),
        actions: [
          ...actions,
          const SizedBox(width: EOSpacing.sm),
        ],
        backgroundColor: transparent
            ? Colors.transparent
            : EOColors.night,
        surfaceTintColor: Colors.transparent,
      );
}

class EONavigationBar extends StatelessWidget {
  const EONavigationBar({
    required this.currentIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  static const destinations = <(IconData, IconData, String)>[
    (Icons.explore_outlined, Icons.explore, 'Explorar'),
    (Icons.groups_outlined, Icons.groups, 'Comunidad'),
    (Icons.map_outlined, Icons.map, 'Mapa'),
    (Icons.route_outlined, Icons.route, 'Rutas'),
    (Icons.shield_outlined, Icons.shield, 'Seguridad'),
    (Icons.person_outline, Icons.person, 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      decoration: const BoxDecoration(
        color: EOColors.surface,
        border: Border(top: BorderSide(color: EOColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _EONavItem(
                  index: i,
                  currentIndex: currentIndex,
                  destination: destinations[i],
                  onTap: onDestinationSelected,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EONavItem extends StatelessWidget {
  const _EONavItem({
    required this.index,
    required this.currentIndex,
    required this.destination,
    required this.onTap,
  });

  final int index;
  final int currentIndex;
  final (IconData, IconData, String) destination;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final selected = index == currentIndex;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.$3,
      child: InkWell(
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? destination.$2 : destination.$1,
              size: selected ? 25 : 23,
              color: selected ? EOColors.green : EOColors.textTertiary,
            ),
            const SizedBox(height: 5),
            Text(
              destination.$3,
              style: EOTextStyles.label.copyWith(
                color: selected ? EOColors.green : EOColors.textTertiary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EOCard extends StatelessWidget {
  const EOCard({
    required this.child,
    this.padding = const EdgeInsets.all(EOSpacing.lg),
    this.onTap,
    this.image,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: EOColors.surface,
        borderRadius: BorderRadius.circular(EORadii.lg),
        border: Border.all(color: EOColors.border),
        image: image == null
            ? null
            : DecorationImage(
                image: image!,
                fit: BoxFit.cover,
                colorFilter: const ColorFilter.mode(
                  Color(0x99000000),
                  BlendMode.darken,
                ),
              ),
      ),
      child: child,
    );
    return onTap == null
        ? content
        : Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(EORadii.lg),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(EORadii.lg),
              child: content,
            ),
          );
  }
}

class EOChip extends StatelessWidget {
  const EOChip({
    required this.label,
    this.icon,
    this.selected = false,
    this.warning = false,
    this.onTap,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool warning;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = warning ? EOColors.orange : EOColors.green;
    return Material(
      color: selected ? color : EOColors.surfaceElevated,
      borderRadius: BorderRadius.circular(EORadii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(EORadii.sm),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(EORadii.sm),
            border: Border.all(color: selected ? color : EOColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? EOColors.white : color),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: EOTextStyles.label.copyWith(
                  color: selected ? EOColors.white : EOColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EOListTile extends StatelessWidget {
  const EOListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: EOSpacing.sm),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: EOSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: EOTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: EOTextStyles.secondary),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: EOSpacing.md),
            trailing!,
          ],
        ],
      ),
    );
    return onTap == null
        ? tile
        : InkWell(onTap: onTap, child: tile);
  }
}

class EOMapPanel extends StatelessWidget {
  const EOMapPanel({
    required this.child,
    this.alignment = Alignment.bottomCenter,
    this.padding = const EdgeInsets.all(EOSpacing.lg),
    this.blur = true,
    super.key,
  });

  final Widget child;
  final Alignment alignment;
  final EdgeInsetsGeometry padding;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: EOColors.night.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(EORadii.lg),
        border: Border.all(color: EOColors.border),
      ),
      child: child,
    );
    final decorated = blur
        ? ClipRRect(
            borderRadius: BorderRadius.circular(EORadii.lg),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: panel,
            ),
          )
        : panel;
    return Align(alignment: alignment, child: decorated);
  }
}

class EOSelect<T> extends StatelessWidget {
  const EOSelect({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelBuilder,
    this.hint,
    super.key,
  });

  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String Function(T value) labelBuilder;
  final String? hint;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        initialValue: value,
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder(item)),
              ),
            )
            .toList(growable: false),
        onChanged: onChanged,
        hint: hint == null ? null : Text(hint!),
        dropdownColor: EOColors.surfaceElevated,
        style: EOTextStyles.body,
        decoration: const InputDecoration(),
      );
}

class EOModal {
  const EOModal._();

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    List<Widget> actions = const [],
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            EOSpacing.lg,
            EOSpacing.md,
            EOSpacing.lg,
            EOSpacing.lg,
          ),
          decoration: const BoxDecoration(
            color: EOColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(EORadii.xl),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: EOColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: EOSpacing.lg),
              Text(title, style: EOTextStyles.title),
              const SizedBox(height: EOSpacing.lg),
              child,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: EOSpacing.lg),
                ...actions,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EOSearchField extends StatelessWidget {
  const EOSearchField({
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.hintText = 'Buscar',
    this.autofocus = false,
    super.key,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hintText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: EOTextStyles.body,
        cursorColor: EOColors.green,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: EOTextStyles.secondary,
          prefixIcon: const Icon(Icons.search, color: EOColors.textTertiary),
          suffixIcon: controller == null
              ? null
              : IconButton(
                  tooltip: 'Borrar búsqueda',
                  onPressed: () => controller!.clear(),
                  icon: const Icon(Icons.close, color: EOColors.textTertiary),
                ),
          filled: true,
          fillColor: EOColors.surfaceElevated,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(EORadii.md),
            borderSide: const BorderSide(color: EOColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(EORadii.md),
            borderSide: const BorderSide(color: EOColors.green, width: 2),
          ),
        ),
      );
}

class EOGpsControl extends StatelessWidget {
  const EOGpsControl({
    required this.onPressed,
    this.tracking = false,
    this.loading = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final bool tracking;
  final bool loading;

  @override
  Widget build(BuildContext context) => EOIconButton(
        icon: loading
            ? Icons.gps_not_fixed
            : tracking
                ? Icons.my_location
                : Icons.location_searching,
        onPressed: onPressed,
        selected: tracking,
        tooltip: tracking ? 'Seguir posición' : 'Centrar en mi posición',
      );
}

class EOMapControls extends StatelessWidget {
  const EOMapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onLayers,
    this.onCompass,
    this.onGps,
    this.gpsTracking = false,
    super.key,
  });

  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onLayers;
  final VoidCallback? onCompass;
  final VoidCallback? onGps;
  final bool gpsTracking;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EOIconButton(icon: Icons.add, onPressed: onZoomIn, tooltip: 'Acercar'),
          const SizedBox(height: 6),
          EOIconButton(icon: Icons.remove, onPressed: onZoomOut, tooltip: 'Alejar'),
          const SizedBox(height: 12),
          EOIconButton(icon: Icons.layers_outlined, onPressed: onLayers, tooltip: 'Capas'),
          if (onCompass != null) ...[
            const SizedBox(height: 6),
            EOIconButton(icon: Icons.explore_outlined, onPressed: onCompass, tooltip: 'Orientación'),
          ],
          if (onGps != null) ...[
            const SizedBox(height: 6),
            EOIconButton(
              icon: Icons.my_location,
              onPressed: onGps,
              selected: gpsTracking,
              tooltip: 'GPS',
            ),
          ],
        ],
      );
}

class EODownloadIndicator extends StatelessWidget {
  const EODownloadIndicator({
    required this.progress,
    this.label,
    this.completed = false,
    this.error = false,
    this.onCancel,
    super.key,
  });

  final double progress;
  final String? label;
  final bool completed;
  final bool error;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final color = error
        ? EOColors.red
        : completed
            ? EOColors.green
            : EOColors.blue;
    return Row(
      children: [
        SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            value: completed || error ? 1 : clamped,
            strokeWidth: 3,
            color: color,
            backgroundColor: EOColors.border,
          ),
        ),
        const SizedBox(width: EOSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null) Text(label!, style: EOTextStyles.body),
              const SizedBox(height: 3),
              Text(
                error
                    ? 'Error en la descarga'
                    : completed
                        ? 'Descarga completada'
                        : '${(clamped * 100).round()} %',
                style: EOTextStyles.secondary,
              ),
            ],
          ),
        ),
        if (!completed && !error && onCancel != null)
          IconButton(
            tooltip: 'Cancelar descarga',
            onPressed: onCancel,
            icon: const Icon(Icons.close, color: EOColors.textSecondary),
          ),
        if (completed)
          const Icon(Icons.check_circle, color: EOColors.green),
      ],
    );
  }
}

class EONavigationBanner extends StatelessWidget {
  const EONavigationBanner({
    required this.instruction,
    required this.distanceLabel,
    this.icon = Icons.turn_right,
    super.key,
  });

  final String instruction;
  final String distanceLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(EOSpacing.lg),
        decoration: BoxDecoration(
          color: EOColors.surface.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(EORadii.lg),
          border: Border.all(color: EOColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 42, color: EOColors.white),
            const SizedBox(width: EOSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(distanceLabel, style: EOTextStyles.hero.copyWith(fontSize: 24)),
                  const SizedBox(height: 2),
                  Text(instruction, style: EOTextStyles.body),
                ],
              ),
            ),
          ],
        ),
      );
}
