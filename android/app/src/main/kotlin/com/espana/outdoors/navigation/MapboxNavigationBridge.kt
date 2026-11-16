package com.espana.outdoors.navigation

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.common.MapboxOptions
import com.mapbox.bindgen.Value
import com.mapbox.common.NetworkRestriction
import com.mapbox.common.TileRegionLoadOptions
import com.mapbox.common.TileStore
import com.mapbox.geojson.Point
import com.mapbox.geojson.Polygon
import com.mapbox.maps.GlyphsRasterizationMode
import com.mapbox.maps.MapboxMapsOptions
import com.mapbox.maps.OfflineManager
import com.mapbox.maps.StylePackLoadOptions
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
import java.io.File

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
        if (navigation != null && configuredToken == accessToken && tileStore != null && offlineManager != null) return

        if (navigation != null) {
            MapboxNavigationProvider.destroy()
            navigation = null
        }
        offlineManager = null

        MapboxOptions.accessToken = accessToken
        val store = getOrCreateProcessTileStore(appContext)
        // Maps SDK v11 reads TileStore credentials from MapboxOptions.
        // The global token is set above, before this persistent TileStore is created.
        tileStore = store

        // Apply Maps SDK globals before constructing any Maps API object.
        // Navigation bootstrap may initialize Maps internals; those objects
        // must inherit the same persistent TileStore used for offline downloads.
        MapboxMapsOptions.tileStore = store
        MapboxMapsOptions.tileStoreUsageMode = TileStoreUsageMode.READ_ONLY
        check(MapboxMapsOptions.tileStore === store) {
            "Maps SDK did not retain the shared offline TileStore before Navigation bootstrap."
        }

        // Navigation receives this same TileStore explicitly through RoutingTilesOptions.
        val routingTilesOptions = RoutingTilesOptions.Builder()
            .tileStore(store)
            .tilesProfile("walking")
            .build()
        navigation = MapboxNavigationProvider.create(
            NavigationOptions.Builder(appContext)
                .routingTilesOptions(routingTilesOptions)
                .build()
        )

        // Reapply and verify after Navigation bootstrap in case the Navigation
        // provider changed global Maps options. OfflineManager and the later Flutter
        // MapWidget must still use the exact same persistent store.
        // READ_ONLY serves downloaded tile packs first and falls back to individual
        // online tiles outside downloaded regions; free panning remains supported.
        MapboxMapsOptions.tileStore = store
        MapboxMapsOptions.tileStoreUsageMode = TileStoreUsageMode.READ_ONLY
        check(MapboxMapsOptions.tileStore === store) {
            "Maps SDK did not retain the shared offline TileStore."
        }
        check(MapboxMapsOptions.tileStoreUsageMode == TileStoreUsageMode.READ_ONLY) {
            "Maps SDK TileStore usage mode must remain READ_ONLY."
        }
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
            .applyDefaultNavigationOptions("walking")
            .coordinatesList(points)
            .steps(true)
            .overview("full")
            .geometries("polyline6")
            .language("es")
            .build()

        engine.requestRoutes(options, object : NavigationRouterCallback {
            override fun onCanceled(routeOptions: RouteOptions, routerOrigin: String) {
                mainHandler.post {
                    result.error("ROUTE_CANCELED", "Mapbox canceled the route request.", null)
                }
            }

            override fun onFailure(reasons: List<RouterFailure>, routeOptions: RouteOptions) {
                // Keep diagnostics useful without exposing the original request URL,
                // which contains the public access token and coordinates.
                val failures = reasons.map { failure ->
                    mapOf(
                        "type" to failure.type.toString(),
                        "routerOrigin" to failure.routerOrigin,
                        "retryable" to failure.isRetryable
                    )
                }
                val summary = failures.joinToString("; ") { failure ->
                    "${failure["type"]} " +
                        "(router=${failure["routerOrigin"]}, retryable=${failure["retryable"]})"
                }.ifBlank { "Mapbox could not calculate this route." }
                mainHandler.post {
                    result.error(
                        "ROUTE_FAILED",
                        summary,
                        mapOf(
                            "failures" to failures,
                            "retryable" to reasons.any { it.isRetryable }
                        )
                    )
                }
            }

            override fun onRoutesReady(routes: List<NavigationRoute>, routerOrigin: String) {
                val source = when (routerOrigin) {
                    RouterOrigin.ONLINE -> "online"
                    RouterOrigin.OFFLINE -> "offline"
                    else -> null
                }
                if (source == null) {
                    mainHandler.post {
                        result.error(
                            "UNKNOWN_ROUTER_ORIGIN",
                            "Mapbox returned a route from an unrecognized router.",
                            mapOf("routerOrigin" to routerOrigin)
                        )
                    }
                    return
                }

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
                    "source" to source,
                    "routerOrigin" to routerOrigin,
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
                    result.error("STYLE_DOWNLOAD_FAILED", "Mapbox style pack download failed.", null)
                }
                return@loadStylePack
            }

            val mapPixelRatio = appContext.resources.displayMetrics.density
            val mapsDescriptor = mapsOffline.createTilesetDescriptor(
                TilesetDescriptorOptions.Builder()
                    .styleURI(styleUri)
                    // Match the tile-pack descriptor to the density used by MapView.
                    // Without this, Maps may request a different tile variant offline.
                    .pixelRatio(mapPixelRatio)
                    .minZoom(minZoom.toByte())
                    .maxZoom(maxZoom.toByte())
                    .build()
            )
            val navigationDescriptor = engine.tilesetDescriptorFactory.getLatest()
            // Keep map and routing packs in separate TileStore regions. A
            // combined progress count can be satisfied by Navigation alone,
            // which previously allowed mapTiles=true without proving any map
            // vector tiles had actually been stored.
            val mapRegionId = "$regionId-maps"
            val routingRegionId = "$regionId-routing-walking"
            val geometry = Polygon.fromLngLats(listOf(ring))
            val mapRegionOptions = TileRegionLoadOptions.Builder()
                .geometry(geometry)
                .descriptors(listOf(mapsDescriptor))
                .networkRestriction(NetworkRestriction.NONE)
                .build()
            val routingRegionOptions = TileRegionLoadOptions.Builder()
                .geometry(geometry)
                .descriptors(listOf(navigationDescriptor))
                .networkRestriction(NetworkRestriction.NONE)
                .build()

            var mapProgress: Map<String, Long> = emptyMap()
            store.loadTileRegion(
                mapRegionId,
                mapRegionOptions,
                { progress ->
                    mapProgress = mapOf(
                        "completedResourceCount" to progress.completedResourceCount,
                        "completedResourceSize" to progress.completedResourceSize,
                        "erroredResourceCount" to progress.erroredResourceCount,
                        "requiredResourceCount" to progress.requiredResourceCount,
                        "loadedResourceCount" to progress.loadedResourceCount,
                        "loadedResourceSize" to progress.loadedResourceSize
                    )
                }
            ) map@ { mapExpected ->
                if (!mapExpected.isValue) {
                    mainHandler.post {
                        result.error(
                            "OFFLINE_MAP_REGION_DOWNLOAD_FAILED",
                            "Mapbox could not download the map tile region.",
                            mapProgress
                        )
                    }
                    return@map
                }

                val downloadedMapRegion = mapExpected.value
                val mapCompleted = mapProgress["completedResourceCount"]
                    ?: downloadedMapRegion?.completedResourceCount
                    ?: 0L
                val mapSize = downloadedMapRegion?.completedResourceSize
                    ?: mapProgress["completedResourceSize"]
                    ?: 0L
                val mapRequired = mapProgress["requiredResourceCount"] ?: 0L
                val mapErrors = mapProgress["erroredResourceCount"] ?: 0L
                if (downloadedMapRegion == null || mapCompleted <= 0 || mapSize <= 0) {
                    mainHandler.post {
                        result.error(
                            "OFFLINE_MAP_REGION_EMPTY",
                            "Mapbox reported no stored map tile resources.",
                            mapProgress
                        )
                    }
                    return@map
                }
                if (mapErrors > 0 || (mapRequired > 0 && mapCompleted < mapRequired)) {
                    mainHandler.post {
                        result.error(
                            "OFFLINE_MAP_REGION_INCOMPLETE",
                            "Mapbox did not complete all required map tile resources.",
                            mapProgress
                        )
                    }
                    return@map
                }

                var routingProgress: Map<String, Long> = emptyMap()
                store.loadTileRegion(
                    routingRegionId,
                    routingRegionOptions,
                    { progress ->
                        routingProgress = mapOf(
                            "completedResourceCount" to progress.completedResourceCount,
                            "completedResourceSize" to progress.completedResourceSize,
                            "erroredResourceCount" to progress.erroredResourceCount,
                            "requiredResourceCount" to progress.requiredResourceCount,
                            "loadedResourceCount" to progress.loadedResourceCount,
                            "loadedResourceSize" to progress.loadedResourceSize
                        )
                    }
                ) routing@ { routingExpected ->
                    if (!routingExpected.isValue) {
                        mainHandler.post {
                            result.error(
                                "OFFLINE_ROUTING_REGION_DOWNLOAD_FAILED",
                                "Mapbox could not download walking routing resources.",
                                routingProgress
                            )
                        }
                        return@routing
                    }

                    val downloadedRoutingRegion = routingExpected.value
                    val routingCompleted = routingProgress["completedResourceCount"]
                        ?: downloadedRoutingRegion?.completedResourceCount
                        ?: 0L
                    val routingSize = downloadedRoutingRegion?.completedResourceSize
                        ?: routingProgress["completedResourceSize"]
                        ?: 0L
                    val routingRequired = routingProgress["requiredResourceCount"] ?: 0L
                    val routingErrors = routingProgress["erroredResourceCount"] ?: 0L
                    if (
                        downloadedRoutingRegion == null ||
                        routingCompleted <= 0 ||
                        routingSize <= 0
                    ) {
                        mainHandler.post {
                            result.error(
                                "OFFLINE_ROUTING_REGION_EMPTY",
                                "Mapbox reported no stored walking routing resources.",
                                routingProgress
                            )
                        }
                        return@routing
                    }
                    if (
                        routingErrors > 0 ||
                        (routingRequired > 0 && routingCompleted < routingRequired)
                    ) {
                        mainHandler.post {
                            result.error(
                                "OFFLINE_ROUTING_REGION_INCOMPLETE",
                                "Mapbox did not complete all required walking routing resources.",
                                routingProgress
                            )
                        }
                        return@routing
                    }

                    // Commit both markers only after the two independent TileStore
                    // regions are complete and non-empty.
                    val markerPersisted = appContext
                        .getSharedPreferences("espana_outdoor_offline", Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean("offline:$regionId:maps", true)
                        .putBoolean("offline:$regionId:routing-walking", true)
                        .putBoolean("offline:$regionId", true)
                        .putString("offline:$regionId:styleUri", styleUri)
                        .putInt("offline:$regionId:minZoom", minZoom)
                        .putInt("offline:$regionId:maxZoom", maxZoom)
                        .putFloat("offline:$regionId:pixelRatio", mapPixelRatio)
                        .commit()
                    if (!markerPersisted) {
                        mainHandler.post {
                            result.error(
                                "OFFLINE_REGION_PERSISTENCE_FAILED",
                                "Offline region metadata could not be committed to persistent storage.",
                                null
                            )
                        }
                        return@routing
                    }

                    val totalCompleted = mapCompleted + routingCompleted
                    val totalSize = mapSize + routingSize
                    val totalRequired = mapRequired + routingRequired
                    val totalErrors = mapErrors + routingErrors
                    val totalLoaded = (mapProgress["loadedResourceCount"] ?: 0L) +
                        (routingProgress["loadedResourceCount"] ?: 0L)
                    val totalLoadedSize = (mapProgress["loadedResourceSize"] ?: 0L) +
                        (routingProgress["loadedResourceSize"] ?: 0L)

                    mainHandler.post {
                        result.success(
                            mapOf(
                                "regionId" to regionId,
                                "mapRegionId" to mapRegionId,
                                "routingRegionId" to routingRegionId,
                                "mapTiles" to true,
                                "routingTiles" to true,
                                "routingProfile" to "walking",
                                "mapPixelRatio" to mapPixelRatio,
                                "mapCompletedResourceCount" to mapCompleted,
                                "mapCompletedResourceSize" to mapSize,
                                "mapRequiredResourceCount" to mapRequired,
                                "mapErroredResourceCount" to mapErrors,
                                "routingCompletedResourceCount" to routingCompleted,
                                "routingCompletedResourceSize" to routingSize,
                                "routingRequiredResourceCount" to routingRequired,
                                "routingErroredResourceCount" to routingErrors,
                                "completedResourceCount" to totalCompleted,
                                "completedResourceSize" to totalSize,
                                "erroredResourceCount" to totalErrors,
                                "requiredResourceCount" to totalRequired,
                                "progressCompletedResourceCount" to totalCompleted,
                                "loadedResourceCount" to totalLoaded,
                                "loadedResourceSize" to totalLoadedSize
                            )
                        )
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
                    result.error("OFFLINE_STATUS_FAILED", "Mapbox could not read the stored offline region list.", null)
                }
                return@getAllTileRegions
            }
            val mapRegionId = "$regionId-maps"
            val routingRegionId = "$regionId-routing-walking"
            val regions = expected.value.orEmpty()
            val mapRegion = regions.firstOrNull { it.id == mapRegionId }
            val routingRegion = regions.firstOrNull { it.id == routingRegionId }
            val preferences = appContext
                .getSharedPreferences("espana_outdoor_offline", Context.MODE_PRIVATE)
            val mapReady = mapRegion != null &&
                mapRegion.completedResourceCount > 0 &&
                mapRegion.completedResourceSize > 0 &&
                preferences.getBoolean("offline:$regionId:maps", false)
            val routingReady = routingRegion != null &&
                routingRegion.completedResourceCount > 0 &&
                routingRegion.completedResourceSize > 0 &&
                preferences.getBoolean("offline:$regionId:routing-walking", false)
            // Legacy combined regions are intentionally not treated as verified:
            // their aggregate progress could be satisfied by routing alone.
            mainHandler.post { result.success(mapReady && routingReady) }
        }
    }


    /**
     * Verify the downloaded Maps descriptor through the exact TileStore exposed
     * to Maps SDK globals, not only through the Navigation bridge's local handle.
     * This distinguishes a region that exists from a region the MapWidget can use.
     */
    fun verifyOfflineRegion(arguments: Any?, result: MethodChannelResult) {
        val regionId = (arguments as? Map<*, *>)?.get("regionId") as? String
        if (regionId.isNullOrBlank()) {
            result.error("INVALID_REGION", "A region ID is required.", null)
            return
        }
        val store = tileStore
        val mapsOffline = offlineManager
        if (store == null || mapsOffline == null) {
            result.error("NAVIGATION_NOT_CONFIGURED", "Configure Mapbox before verifying offline data.", null)
            return
        }

        val preferences = appContext
            .getSharedPreferences("espana_outdoor_offline", Context.MODE_PRIVATE)
        val styleUri = preferences.getString("offline:$regionId:styleUri", null)
        val minZoom = preferences.getInt("offline:$regionId:minZoom", -1)
        val maxZoom = preferences.getInt("offline:$regionId:maxZoom", -1)
        val pixelRatio = preferences.getFloat("offline:$regionId:pixelRatio", -1f)
        if (styleUri.isNullOrBlank() || minZoom < 0 || maxZoom < minZoom || pixelRatio <= 0f) {
            mainHandler.post {
                result.success(
                    mapOf(
                        "mapTileStoreSameInstance" to false,
                        "mapDescriptorCheckCompleted" to false,
                        "mapDescriptorPresentInMapsStore" to false,
                        "mapRegionPresent" to false,
                        "routingRegionPresent" to false,
                        "tileStoreUsageModeReadOnly" to
                            (MapboxMapsOptions.tileStoreUsageMode == TileStoreUsageMode.READ_ONLY)
                    )
                )
            }
            return
        }

        val mapsStore = MapboxMapsOptions.tileStore
        val mapStoreSameInstance = mapsStore === store
        val descriptorStore = mapsStore ?: store
        val mapRegionId = "$regionId-maps"
        val routingRegionId = "$regionId-routing-walking"
        val mapDescriptor = mapsOffline.createTilesetDescriptor(
            TilesetDescriptorOptions.Builder()
                .styleURI(styleUri)
                .pixelRatio(pixelRatio)
                .minZoom(minZoom.toByte())
                .maxZoom(maxZoom.toByte())
                .build()
        )

        store.getAllTileRegions { regionsExpected ->
            if (!regionsExpected.isValue) {
                mainHandler.post {
                    result.error(
                        "OFFLINE_STATUS_FAILED",
                        "Mapbox could not read the stored offline region list.",
                        null
                    )
                }
                return@getAllTileRegions
            }
            val regions = regionsExpected.value.orEmpty()
            val mapRegion = regions.firstOrNull { it.id == mapRegionId }
            val routingRegion = regions.firstOrNull { it.id == routingRegionId }
            val mapRegionPresent = mapRegion != null &&
                mapRegion.completedResourceCount > 0 &&
                mapRegion.completedResourceSize > 0 &&
                preferences.getBoolean("offline:$regionId:maps", false)
            val routingRegionPresent = routingRegion != null &&
                routingRegion.completedResourceCount > 0 &&
                routingRegion.completedResourceSize > 0 &&
                preferences.getBoolean("offline:$regionId:routing-walking", false)

            descriptorStore.tileRegionContainsDescriptors(mapRegionId, listOf(mapDescriptor)) { descriptorExpected ->
                val descriptorCheckCompleted = descriptorExpected.isValue
                val descriptorPresent = descriptorCheckCompleted && descriptorExpected.value == true
                mainHandler.post {
                    result.success(
                        mapOf(
                            "mapTileStoreSameInstance" to mapStoreSameInstance,
                            "mapDescriptorCheckCompleted" to descriptorCheckCompleted,
                            "mapDescriptorPresentInMapsStore" to descriptorPresent,
                            "mapRegionPresent" to mapRegionPresent,
                            "routingRegionPresent" to routingRegionPresent,
                            "tileStoreUsageModeReadOnly" to
                                (MapboxMapsOptions.tileStoreUsageMode == TileStoreUsageMode.READ_ONLY),
                            "mapPixelRatio" to pixelRatio
                        )
                    )
                }
            }
        }
    }

    @Synchronized
    fun destroy() {
        if (navigation != null) {
            MapboxNavigationProvider.destroy()
            navigation = null
        }
        offlineManager = null
        configuredToken = null
        // Keep the process-wide TileStore alive; its files remain on disk.

    }

    private companion object {
        private const val TILE_STORE_DIRECTORY = "mapbox-tiles"

        @Volatile
        private var processTileStore: TileStore? = null

        @Synchronized
        private fun getOrCreateProcessTileStore(context: Context): TileStore {
            processTileStore?.let { return it }

            // Keep offline resources private and persistent, but outside Android backup.
            val directory = File(context.noBackupFilesDir, TILE_STORE_DIRECTORY)
            check(directory.isDirectory || directory.mkdirs()) {
                "Could not create the persistent Mapbox TileStore directory."
            }
            val path = directory.absolutePath + File.separator
            val rootPath = TileStore.setRootPath(path)
            check(rootPath.isValue) {
                "Could not set the persistent Mapbox TileStore root path: $rootPath"
            }
            return TileStore.create().also { processTileStore = it }
        }
    }
}

typealias MethodChannelResult = io.flutter.plugin.common.MethodChannel.Result
