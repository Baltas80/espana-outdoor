package com.espana.outdoors.navigation

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.common.MapboxOptions
import com.mapbox.common.TileStore
import com.mapbox.geojson.Point
import com.mapbox.maps.MapboxMapsOptions
import com.mapbox.navigation.base.extensions.applyDefaultNavigationOptions
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.base.options.RoutingTilesOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.base.route.NavigationRouterCallback
import com.mapbox.navigation.base.route.RouterOrigin
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.MapboxNavigationProvider
import io.flutter.plugin.common.MethodChannel

/**
 * Route-only bridge. It deliberately uses the SDK default TileStore root,
 * matching Mapbox Maps' existing default store; it never changes or deletes
 * the TileStore root and does not manage visual map downloads.
 */
class MapboxNavigationBridge(context: Context) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private var navigation: MapboxNavigation? = null
    private var tileStore: TileStore? = null

    @Synchronized
    fun configure(accessToken: String) {
        require(accessToken.startsWith("pk.")) { "A public Mapbox access token is required." }
        if (navigation != null && tileStore != null) return

        MapboxOptions.accessToken = accessToken
        val store = TileStore.create()
        tileStore = store
        MapboxMapsOptions.tileStore = store

        val routingTiles = RoutingTilesOptions.Builder()
            .tileStore(store)
            .tilesProfile("walking")
            .build()
        navigation = MapboxNavigationProvider.create(
            NavigationOptions.Builder(appContext)
                .routingTilesOptions(routingTiles)
                .build()
        )
        MapboxMapsOptions.tileStore = store
        check(MapboxMapsOptions.tileStore === store) {
            "Maps and Navigation did not retain the same TileStore instance."
        }
    }

    fun requestRoute(arguments: Any?, result: MethodChannel.Result) {
        val engine = navigation
        if (engine == null) {
            result.error("NAVIGATION_NOT_CONFIGURED", "Mapbox Navigation is not initialized.", null)
            return
        }
        val rawPoints = (arguments as? Map<*, *>)?.get("points") as? List<*>
        if (rawPoints == null || rawPoints.size < 2 || rawPoints.size > 25) {
            result.error("INVALID_POINTS", "A route requires between 2 and 25 coordinates.", null)
            return
        }
        val points = try {
            rawPoints.map { raw ->
                val pair = raw as? List<*> ?: error("Invalid coordinate pair.")
                require(pair.size >= 2)
                val longitude = (pair[0] as Number).toDouble()
                val latitude = (pair[1] as Number).toDouble()
                require(longitude.isFinite() && longitude in -180.0..180.0)
                require(latitude.isFinite() && latitude in -90.0..90.0)
                Point.fromLngLat(longitude, latitude)
            }
        } catch (error: Throwable) {
            result.error("INVALID_POINTS", error.message, null)
            return
        }

        val options = RouteOptions.builder()
            .applyDefaultNavigationOptions("walking")
            .coordinatesList(points)
            .steps(true)
            .overview("full")
            .geometries("polyline6")
            .language("es")
            .build()

        engine.requestRoutes(options, object : NavigationRouterCallback {
            override fun onCanceled(routeOptions: RouteOptions, routerOrigin: String) {
                mainHandler.post { result.error("ROUTE_CANCELED", "Mapbox canceled the route request.", null) }
            }

            override fun onFailure(
                reasons: List<com.mapbox.navigation.base.route.RouterFailure>,
                routeOptions: RouteOptions
            ) {
                val summary = reasons.joinToString("; ") { it.type.toString() }
                    .ifBlank { "Mapbox could not calculate this route." }
                mainHandler.post { result.error("ROUTE_FAILED", summary, null) }
            }

            override fun onRoutesReady(routes: List<NavigationRoute>, routerOrigin: String) {
                val source = when (routerOrigin) {
                    RouterOrigin.ONLINE -> "online"
                    RouterOrigin.OFFLINE -> "offline"
                    else -> null
                }
                if (source == null) {
                    mainHandler.post {
                        result.error("UNKNOWN_ROUTER_ORIGIN", "Unrecognized Mapbox router origin.", null)
                    }
                    return
                }
                val route = routes.firstOrNull()?.directionsRoute
                val geometry = route?.geometry()
                if (route == null || geometry.isNullOrBlank()) {
                    mainHandler.post { result.error("EMPTY_ROUTE", "Mapbox returned no route geometry.", null) }
                    return
                }
                val steps = route.legs().orEmpty().flatMap { it.steps().orEmpty() }.mapNotNull { step ->
                    val instruction = step.maneuver()?.instruction()?.trim().orEmpty()
                    if (instruction.isEmpty()) null else mapOf(
                        "instruction" to instruction,
                        "distanceMeters" to step.distance(),
                        "durationSeconds" to step.duration()
                    )
                }
                mainHandler.post {
                    result.success(
                        mapOf(
                            "geometry" to geometry,
                            "distanceMeters" to route.distance(),
                            "durationSeconds" to route.duration(),
                            "source" to source,
                            "steps" to steps
                        )
                    )
                }
            }
        })
    }

    @Synchronized
    fun destroy() {
        if (navigation != null) MapboxNavigationProvider.destroy()
        navigation = null
        // Keep TileStore alive and its persistent data untouched.
    }
}
