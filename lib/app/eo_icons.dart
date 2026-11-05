import 'package:flutter/material.dart';

/// Canonical semantic icon catalogue for España Outdoor.
///
/// Prefer these symbols over direct Material icon references in feature UI.
/// Geometry is deliberately simple and consistent at 20–28 logical pixels.
abstract final class EOIcons {
  // Core navigation
  static const explore = Icons.explore_outlined;
  static const map = Icons.map_outlined;
  static const routes = Icons.route_outlined;
  static const navigation = Icons.navigation_outlined;
  static const safety = Icons.health_and_safety_outlined;
  static const profile = Icons.person_outline;
  static const search = Icons.search_rounded;
  static const menu = Icons.menu_rounded;
  static const close = Icons.close_rounded;
  static const back = Icons.arrow_back_rounded;
  static const settings = Icons.tune_rounded;
  static const layers = Icons.layers_outlined;

  // Position and movement
  static const gps = Icons.my_location_rounded;
  static const compass = Icons.explore_outlined;
  static const location = Icons.location_on_outlined;
  static const routeStart = Icons.play_arrow_rounded;
  static const routeStop = Icons.stop_rounded;
  static const routePause = Icons.pause_rounded;
  static const turnLeft = Icons.turn_left_rounded;
  static const turnRight = Icons.turn_right_rounded;
  static const straight = Icons.straight_rounded;
  static const zoomIn = Icons.add_rounded;
  static const zoomOut = Icons.remove_rounded;

  // Outdoor features
  static const download = Icons.offline_pin_outlined;
  static const downloaded = Icons.cloud_done_outlined;
  static const weather = Icons.wb_cloudy_outlined;
  static const nature = Icons.forest_outlined;
  static const astronomy = Icons.nights_stay_outlined;
  static const pets = Icons.pets_outlined;
  static const wildlife = Icons.pest_control_rodent_outlined;
  static const cycling = Icons.directions_bike_rounded;
  static const hiking = Icons.hiking_rounded;
  static const gpx = Icons.file_open_outlined;
  static const recording = Icons.fiber_manual_record_rounded;

  // Safety and status
  static const rescue = Icons.sos_rounded;
  static const warning = Icons.warning_amber_rounded;
  static const error = Icons.error_outline_rounded;
  static const check = Icons.check_circle_outline_rounded;
  static const information = Icons.info_outline_rounded;
  static const emergency = Icons.emergency_rounded;
}
