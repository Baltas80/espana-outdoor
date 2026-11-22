package com.example.espana_outdoors

import com.espana.outdoors.navigation.MapboxNavigationBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var navigationBridge: MapboxNavigationBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bridge = MapboxNavigationBridge(applicationContext)
        navigationBridge = bridge

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NAVIGATION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val accessToken = call.argument<String>("accessToken")
                    if (accessToken.isNullOrBlank()) {
                        result.error(
                            "MISSING_ACCESS_TOKEN",
                            "A Mapbox access token is required.",
                            null
                        )
                    } else {
                        try {
                            bridge.configure(accessToken)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "NAVIGATION_CONFIGURATION_FAILED",
                                error.message,
                                null
                            )
                        }
                    }
                }

                "requestRoute" -> bridge.requestRoute(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        navigationBridge?.destroy()
        navigationBridge = null
        super.onDestroy()
    }

    private companion object {
        const val NAVIGATION_CHANNEL = "com.espanaoutdoors/navigation"
    }
}
