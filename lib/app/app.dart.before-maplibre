import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/contracts/routing_service.dart';
import '../core/gpx/gpx_import_service.dart';
import '../core/models/route_summary.dart';
import '../features/alerts/alerts_page.dart';
import '../features/astronomy/astronomy_page.dart';
import '../features/explore/explore_page.dart';
import '../features/home/home_page.dart';
import '../features/instruments/instruments_page.dart';
import '../features/map/map_page.dart';
import '../features/navigation/backtrack_page.dart';
import '../features/navigation/navigation_page.dart';
import '../features/navigation/waypoints_page.dart';
import '../features/natura/natura_protect_page.dart';
import '../features/offline/offline_page.dart';
import '../features/pets/pets_page.dart';
import '../features/profile/plans_page.dart';
import '../features/profile/profile_page.dart';
import '../features/rescue/rescue_link_page.dart';
import '../features/routes/route_detail_page.dart';
import '../features/routes/route_planner_page.dart';
import '../features/routes/routes_page.dart';
import '../features/safety/safety_page.dart';
import '../features/safety/trusted_contacts_page.dart';
import '../features/shop/shop_page.dart';
import '../features/splash/splash_page.dart';
import '../features/weather/lightning_page.dart';
import '../features/wildlife/wildlife_page.dart';
import 'app_shell.dart';
import 'theme.dart';

class EspanaOutdoorApp extends StatelessWidget {
  const EspanaOutdoorApp({super.key});

  static Widget _withBackNavigation(
    Widget child, {
    String fallback = '/',
  }) =>
      _BackNavigationScope(fallback: fallback, child: child);

  static final _router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, __) => const HomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (_, __) => _withBackNavigation(const MapPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/routes',
                builder: (_, __) => _withBackNavigation(const RoutesPage()),
                routes: [
                  GoRoute(
                    path: 'planner',
                    builder: (_, __) => _withBackNavigation(
                      const RoutePlannerPage(),
                      fallback: '/routes',
                    ),
                  ),
                  GoRoute(
                    path: 'detail',
                    builder: (_, state) {
                      final extra = state.extra;
                      return _withBackNavigation(
                        RouteDetailPage(
                          route: extra is RouteSummary ? extra : null,
                          track: extra is ImportedTrack ? extra : null,
                        ),
                        fallback: '/routes',
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/safety',
                builder: (_, __) => _withBackNavigation(const SafetyPage()),
                routes: [
                  GoRoute(
                    path: 'contacts',
                    builder: (_, __) => _withBackNavigation(
                      const TrustedContactsPage(),
                      fallback: '/safety',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => _withBackNavigation(const ProfilePage()),
                routes: [
                  GoRoute(
                    path: 'plans',
                    builder: (_, __) => _withBackNavigation(
                      const PlansPage(),
                      fallback: '/profile',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/explore', builder: (_, __) => _withBackNavigation(const ExplorePage())),
      GoRoute(path: '/shop', builder: (_, __) => _withBackNavigation(const ShopPage())),
      GoRoute(
        path: '/navigation',
        builder: (_, state) {
          final route = state.extra is RouteResult ? state.extra as RouteResult : null;
          return _withBackNavigation(NavigationPage(route: route), fallback: '/map');
        },
      ),
      GoRoute(
        path: '/navigation/backtrack',
        builder: (_, __) => _withBackNavigation(const BacktrackPage(), fallback: '/navigation'),
      ),
      GoRoute(
        path: '/navigation/waypoints',
        builder: (_, __) => _withBackNavigation(const WaypointsPage(), fallback: '/navigation'),
      ),
      GoRoute(path: '/instruments', builder: (_, __) => _withBackNavigation(const InstrumentsPage())),
      GoRoute(path: '/astronomy', builder: (_, __) => _withBackNavigation(const AstronomyPage(), fallback: '/instruments')),
      GoRoute(path: '/weather/lightning', builder: (_, __) => _withBackNavigation(const LightningPage(), fallback: '/instruments')),
      GoRoute(path: '/pets', builder: (_, __) => _withBackNavigation(const PetsPage())),
      GoRoute(path: '/wildlife', builder: (_, __) => _withBackNavigation(const WildlifePage())),
      GoRoute(path: '/natura', builder: (_, __) => _withBackNavigation(const NaturaProtectPage())),
      GoRoute(path: '/alerts', builder: (_, __) => _withBackNavigation(const AlertsPage())),
      GoRoute(path: '/rescue', builder: (_, __) => _withBackNavigation(const RescueLinkPage())),
      GoRoute(path: '/offline', builder: (_, __) => _withBackNavigation(const OfflinePage())),
    ],
  );

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'España Outdoor',
        debugShowCheckedModeBanner: false,
        theme: buildOutdoorTheme(Brightness.light),
        darkTheme: buildOutdoorTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        routerConfig: _router,
      );
}

class _BackNavigationScope extends StatelessWidget {
  const _BackNavigationScope({required this.child, required this.fallback});
  final Widget child;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !canPop) context.go(fallback);
      },
      child: child,
    );
  }
}
