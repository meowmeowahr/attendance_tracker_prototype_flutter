package org.mckinneysteamacademy.second

import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "org.mckinneysteamacademy.second/lockdown"

    // Flag to control volume key absorption
    private var absorbVolumeKeys = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->

            when (call.method) {
                "isDefaultLauncher" -> {
                    val isDefault = isDefaultLauncher()
                    result.success(isDefault)
                }
                "restartToHome" -> {
                    restartApp()
                    result.success(null)
                }
                "setAbsorbVolumeKeys" -> {
                    val enable = call.argument<Boolean>("enabled") ?: false
                    absorbVolumeKeys = enable
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Detect if this app is the current default launcher */
    fun isDefaultLauncher(): Boolean {
        val filter = IntentFilter(Intent.ACTION_MAIN)
        filter.addCategory(Intent.CATEGORY_HOME)

        val filters = mutableListOf<IntentFilter>()
        filters.add(filter)

        val myPackageName = packageName
        val activities = mutableListOf<ComponentName>()
        val packageManager = packageManager

        // The third argument can be null or a specific user
        packageManager.getPreferredActivities(filters, activities, null)

        for (activity in activities) {
            if (myPackageName == activity.packageName) {
                return true
            }
        }
        return false
    }

    /** Restart the app as HOME/launcher */
    fun restartApp() {
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        startActivity(intent)
        finish()
    }

    /** Absorb volume keys if flag is enabled */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (absorbVolumeKeys && (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (absorbVolumeKeys && (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }
}
