package com.example.espana_outdoors

import android.util.Log
import com.espana.outdoors.navigation.MapboxNavigationBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val logTag = "EspanaOutdoorBootstrap"
    private lateinit var navigationBridge: MapboxNavigationBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i(logTag, "flutter_engine_configured")
        navigationBridge = MapboxNavigationBridge(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.espanaoutdoors/navigation"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val token = call.argument<String>("accessToken")
                    if (token.isNullOrBlank()) {
                        result.error("MISSING_TOKEN", "Mapbox access token is required.", null)
                    } else {
                        Log.i(logTag, "mapbox_navigation_configure_started")
                        runCatching { navigationBridge.configure(token) }
                            .onSuccess {
                                Log.i(logTag, "mapbox_navigation_configured")
                                result.success(null)
                            }
                            .onFailure { error ->
                                // Log only the exception type; never emit token-bearing SDK messages.
                                Log.e(
                                    logTag,
                                    "mapbox_navigation_configuration_failed type=${error.javaClass.simpleName}"
                                )
                                result.error("NAVIGATION_INIT_FAILED", "Mapbox Navigation initialization failed.", null)
                            }
                    }
                }
                "requestRoute" -> navigationBridge.requestRoute(call.arguments, result)
                "downloadOfflineRegion" -> navigationBridge.downloadOfflineRegion(call.arguments, result)
                "hasOfflineRegion" -> navigationBridge.hasOfflineRegion(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (::navigationBridge.isInitialized) navigationBridge.destroy()
        super.onDestroy()
    }
}
