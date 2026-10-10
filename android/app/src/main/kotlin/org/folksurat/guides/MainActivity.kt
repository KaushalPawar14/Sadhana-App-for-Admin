package org.folksurat.guides

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Which package installed this app (the Play Store is "com.android.vending").
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "folk/install_source")
            .setMethodCallHandler { call, result ->
                if (call.method == "installer") {
                    result.success(installerPackage())
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun installerPackage(): String? {
        return try {
            if (Build.VERSION.SDK_INT >= 30) {
                packageManager.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName)
            }
        } catch (e: Exception) {
            null
        }
    }
}
