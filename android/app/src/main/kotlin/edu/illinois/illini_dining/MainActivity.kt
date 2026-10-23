package edu.illinois.illini_dining

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
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPause() {
        super.onPause()
        CookieManager.getInstance().flush()
    }
}
