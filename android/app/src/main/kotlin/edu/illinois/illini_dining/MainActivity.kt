package edu.illinois.illini_dining

import android.net.Uri
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Counterpart of SessionCookieKeeper in ios/Runner/AppDelegate.swift.
        // Android's WebView already keeps session cookies across restarts
        // (Chromium's android_webview cookie store persists and restores
        // them), so there's nothing to restore; it only writes cookies to disk
        // in batches, so flush after signing in to make sure a sign-in
        // survives the app being closed right away.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "illini_dining/session_cookies")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "restore" -> result.success(0)
                    "save", "clear" -> {
                        CookieManager.getInstance().flush()
                        result.success(null)
                    }
                    "describe" -> result.success(mapOf("cookies" to describeSignInCookies()))
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "illini_dining/map_gestures")
            .setMethodCallHandler { call, result ->
                val dragUpZoomsIn = call.arguments as? Boolean
                if (call.method != "setDragUpZoomsIn" || dragUpZoomsIn == null) {
                    return@setMethodCallHandler result.notImplemented()
                }
                result.success(mapZoomGesture.apply(window.decorView, dragUpZoomsIn))
            }
    }

    private val mapZoomGesture = MapZoomGesture()

    /**
     * Names of the cookies the WebView would send to each sign-in site, for the
     * app's sign-in diagnostics screen. Android's CookieManager only gives
     * name=value pairs, so lifetimes are unknown, and values are dropped here.
     */
    private fun describeSignInCookies(): List<Map<String, String>> {
        val manager = CookieManager.getInstance()
        return signInPages.flatMap { url ->
            val host = Uri.parse(url).host ?: return@flatMap emptyList()
            (manager.getCookie(url) ?: "").split(";")
                .map { it.substringBefore("=").trim() }
                .filter { it.isNotEmpty() }
                .map { mapOf("name" to it, "host" to host) }
        }
    }

    override fun onPause() {
        super.onPause()
        CookieManager.getInstance().flush()
    }
}

private val signInPages = listOf(
    "https://web.housing.illinois.edu/MyHousing/",
    "https://shibboleth.illinois.edu/idp/",
    "https://login.microsoftonline.com/",
    "https://login.microsoft.com/",
)
