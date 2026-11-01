package com.streamflow.streamflow

import android.app.PictureInPictureParams
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var mcLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Service d'enregistrement en arriere-plan.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "streamflow/background")
            .setMethodCallHandler { call, result ->
                val i = Intent(this, RecordingService::class.java)
                try {
                    when (call.method) {
                        "start" -> {
                            i.putExtra("title", call.argument<String>("title"))
                            i.putExtra("text", call.argument<String>("text"))
                            i.putExtra("active", call.argument<Boolean>("active") ?: true)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
                            else startService(i)
                            result.success(true)
                        }
                        "stop" -> { stopService(i); result.success(true) }
                        "multicastLock" -> {
                            val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                            if (call.arguments as? Boolean == true) {
                                if (mcLock == null) mcLock = wm.createMulticastLock("StreamFlow:cast").apply {
                                    setReferenceCounted(false); acquire()
                                }
                            } else {
                                mcLock?.let { if (it.isHeld) it.release() }
                                mcLock = null
                            }
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.success(false)
                }
            }
        // Image dans l'image : appelee depuis le lecteur.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "streamflow/pip")
            .setMethodCallHandler { call, result ->
                if (call.method == "enter" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val w = (call.argument<Int>("w") ?: 16).coerceAtLeast(1)
                    val h = (call.argument<Int>("h") ?: 9).coerceAtLeast(1)
                    // Android limite le format entre 1:2.39 et 2.39:1.
                    val ratio = Rational(w, h)
                    val safe = if (ratio.toFloat() > 2.39f) Rational(239, 100)
                        else if (ratio.toFloat() < 0.418f) Rational(100, 239)
                        else ratio
                    try {
                        enterPictureInPictureMode(
                            PictureInPictureParams.Builder().setAspectRatio(safe).build()
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
