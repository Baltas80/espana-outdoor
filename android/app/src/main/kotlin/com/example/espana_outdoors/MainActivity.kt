package com.example.espana_outdoors

import com.espana.outdoors.navigation.MapboxNavigationBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var navigationBridge: MapboxNavigationBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                        runCatching { navigationBridge.configure(token) }
                            .onSuccess { result.success(null) }
                            .onFailure {
                                result.error("NAVIGATION_INIT_FAILED", it.message, null)
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
