package com.espana.outdoors.navigation

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.common.MapboxOptions
import com.mapbox.common.TileStore
import com.mapbox.common.Value
import com.mapbox.geojson.Point
import com.mapbox.geojson.Polygon
import com.mapbox.maps.GlyphsRasterizationMode
import com.mapbox.maps.MapboxMapsOptions
import com.mapbox.maps.OfflineManager
import com.mapbox.maps.StylePackLoadOptions
import com.mapbox.maps.TileRegionLoadOptions
import com.mapbox.maps.TileStoreUsageMode
import com.mapbox.maps.TilesetDescriptorOptions
import com.mapbox.navigation.base.extensions.applyDefaultNavigationOptions
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.base.options.RoutingTilesOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.base.route.NavigationRouterCallback
import com.mapbox.navigation.base.route.RouterFailure
import com.mapbox.navigation.base.route.RouterOrigin
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.MapboxNavigationProvider

class MapboxNavigationBridge(context: Context) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private var tileStore: TileStore? = null
    private var offlineManager: OfflineManager? = null
    private var navigation: MapboxNavigation? = null
    private var configuredToken: String? = null

    @Synchronized
    fun configure(accessToken: String) {
        require(accessToken.startsWith("pk.")) {
            "A public Mapbox access token (pk.) is required."
        }
        if (navigation != null && configuredToken == accessToken) return

        MapboxOptions.accessToken = accessToken
        val store = tileStore ?: TileStore.create().also { tileStore = it }
        // This same TileStore is used by Maps and Navigation for every offline region.
        MapboxMapsOptions.tileStore = store
        MapboxMapsOptions.tileStoreUsageMode = TileStoreUsageMode.READ_AND_UPDATE

        val routingTilesOptions = RoutingTilesOptions.Builder()
            .tileStore(store)
            .tilesProfile("walking")
            .build()
        navigation = MapboxNavigationProvider.create(
            NavigationOptions.Builder(appContext)
                .routingTilesOptions(routingTilesOptions)
                .build()
        )
        offlineManager = OfflineManager()
        configuredToken = accessToken
    }

    fun requestRoute(arguments: Any?, result: MethodChannelResult) {
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
                val pair = raw as? List<*>
                    ?: throw IllegalArgumentException("Invalid coordinate pair.")
                require(pair.size >= 2) { "Invalid coordinate pair." }
                val longitude = (pair[0] as? Number)?.toDouble()
                    ?: throw IllegalArgumentException("Invalid longitude.")
                val latitude = (pair[1] as? Number)?.toDouble()
                    ?: throw IllegalArgumentException("Invalid latitude.")
                require(longitude.isFinite() && longitude in -180.0..180.0)
                require(latitude.isFinite() && latitude in -90.0..90.0)
                Point.fromLngLat(longitude, latitude)
            }
        } catch (error: Throwable) {
            result.error("INVALID_POINTS", error.message, null)
            return
        }

        val options = RouteOptions.builder()
            .applyDefaultNavigationOptions()
            .profile("mapbox/walking")
            .coordinatesList(points)
            .steps(true)
            .overview("full")
            .geometry("polyline6")
            .language("es")
            .build()

        engine.requestRoutes(options, object : NavigationRouterCallback {
            override fun onCanceled(routeOptions: RouteOptions, routerOrigin: String) {
                mainHandler.post {
                    result.error("ROUTE_CANCELED", "Mapbox canceled the route request.", null)
                }
            }

            override fun onFailure(reasons: List<RouterFailure>, routeOptions: RouteOptions) {
                mainHandler.post {
                    result.error(
                        "ROUTE_FAILED",
                        reasons.joinToString("; ") { it.toString() }.ifBlank {
                            "Mapbox could not calculate this route."
                        },
                        null
                    )
                }
            }

            override fun onRoutesReady(routes: List<NavigationRoute>, routerOrigin: String) {
                val route = routes.firstOrNull()?.directionsRoute
                val geometry = route?.geometry()
                if (route == null || geometry.isNullOrBlank()) {
                    mainHandler.post {
                        result.error("EMPTY_ROUTE", "Mapbox returned no usable route geometry.", null)
                    }
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
                val response = mapOf(
                    "geometry" to geometry,
                    "distanceMeters" to route.distance(),
                    "durationSeconds" to route.duration(),
                    "source" to if (routerOrigin == RouterOrigin.OFFLINE) "offline" else "online",
                    "steps" to steps
                )
                mainHandler.post { result.success(response) }
            }
        })
    }

    fun downloadOfflineRegion(arguments: Any?, result: MethodChannelResult) {
        val args = arguments as? Map<*, *>
        val regionId = args?.get("regionId") as? String
        val styleUri = args?.get("styleUri") as? String
        val rawRing = args?.get("coordinates") as? List<*>
        val minZoom = (args?.get("minZoom") as? Number)?.toInt() ?: 8
        val maxZoom = (args?.get("maxZoom") as? Number)?.toInt() ?: 15
        if (regionId.isNullOrBlank() || styleUri.isNullOrBlank()) {
            result.error("INVALID_REGION", "A region ID and style URI are required.", null)
            return
        }
        if (rawRing == null || rawRing.size < 4 || minZoom < 0 || maxZoom < minZoom || maxZoom > 22) {
            result.error("INVALID_GEOMETRY", "The offline region geometry or zoom range is invalid.", null)
            return
        }
        val ring = try {
            rawRing.map { raw ->
                val pair = raw as? List<*>
                    ?: throw IllegalArgumentException("Invalid polygon coordinate.")
                require(pair.size >= 2) { "Invalid polygon coordinate." }
                val longitude = (pair[0] as? Number)?.toDouble()
                    ?: throw IllegalArgumentException("Invalid longitude.")
                val latitude = (pair[1] as? Number)?.toDouble()
                    ?: throw IllegalArgumentException("Invalid latitude.")
                require(longitude.isFinite() && longitude in -180.0..180.0)
                require(latitude.isFinite() && latitude in -90.0..90.0)
                Point.fromLngLat(longitude, latitude)
            }
        } catch (error: Throwable) {
            result.error("INVALID_GEOMETRY", error.message, null)
            return
        }

        val engine = navigation
        val store = tileStore
        val mapsOffline = offlineManager
        if (engine == null || store == null || mapsOffline == null) {
            result.error("NAVIGATION_NOT_CONFIGURED", "Configure Mapbox before downloading offline data.", null)
            return
        }

        val styleOptions = StylePackLoadOptions.Builder()
            .glyphsRasterizationMode(GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY)
            .metadata(Value(regionId))
            .acceptExpired(false)
            .build()

        mapsOffline.loadStylePack(
            styleUri,
            styleOptions,
            { /* Native Mapbox download progress. */ }
        ) { styleExpected ->
            if (!styleExpected.isValue) {
                mainHandler.post {
                    result.error("STYLE_DOWNLOAD_FAILED", styleExpected.toString(), null)
                }
                return@loadStylePack
            }

            val mapsDescriptor = mapsOffline.createTilesetDescriptor(
                TilesetDescriptorOptions.Builder()
                    .styleURI(styleUri)
                    .minZoom(minZoom)
                    .maxZoom(maxZoom)
                    .build()
            )
            val navigationDescriptor = engine.tilesetDescriptorFactory.getLatest()
            val regionOptions = TileRegionLoadOptions.Builder()
                .geometry(Polygon.fromLngLats(listOf(ring)))
                .descriptors(listOf(mapsDescriptor, navigationDescriptor))
                .build()

            store.loadTileRegion(
                regionId,
                regionOptions,
                { /* Native Mapbox download progress. */ }
            ) { tileExpected ->
                if (tileExpected.isValue) {
                    appContext.getSharedPreferences("espana_outdoor_offline", Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean("offline:$regionId", true)
                        .apply()
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "regionId" to regionId,
                                "mapTiles" to true,
                                "routingProfile" to "walking"
                            )
                        )
                    }
                } else {
                    mainHandler.post {
                        result.error("OFFLINE_REGION_DOWNLOAD_FAILED", tileExpected.toString(), null)
                    }
                }
            }
        }
    }

    fun hasOfflineRegion(arguments: Any?, result: MethodChannelResult) {
        val regionId = (arguments as? Map<*, *>)?.get("regionId") as? String
        if (regionId.isNullOrBlank()) {
            result.error("INVALID_REGION", "A region ID is required.", null)
            return
        }
        val store = tileStore
        if (store == null) {
            result.success(false)
            return
        }
        store.getAllTileRegions { expected ->
            if (!expected.isValue) {
                mainHandler.post {
                    result.error("OFFLINE_STATUS_FAILED", expected.toString(), null)
                }
                return@getAllTileRegions
            }
            val exists = expected.value.orEmpty().any { it.id == regionId } &&
                appContext.getSharedPreferences("espana_outdoor_offline", Context.MODE_PRIVATE)
                    .getBoolean("offline:$regionId", false)
            mainHandler.post { result.success(exists) }
        }
    }

    @Synchronized
    fun destroy() {
        if (navigation != null) {
            MapboxNavigationProvider.destroy()
            navigation = null
        }
    }
}

typealias MethodChannelResult = io.flutter.plugin.common.MethodChannel.Result
