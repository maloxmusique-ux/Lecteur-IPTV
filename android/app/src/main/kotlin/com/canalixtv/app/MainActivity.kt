package com.canalixtv.app

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

    // Mini-lecteur automatique quand on quitte l'app pendant une lecture.
    private var autoPip = false
    private var pipRatio = Rational(16, 9)

    private fun safeRatio(w: Int, h: Int): Rational {
        // Android limite le format entre 1:2.39 et 2.39:1.
        val ratio = Rational(w.coerceAtLeast(1), h.coerceAtLeast(1))
        return if (ratio.toFloat() > 2.39f) Rational(239, 100)
            else if (ratio.toFloat() < 0.418f) Rational(100, 239)
            else ratio
    }

    private fun pipParams(): PictureInPictureParams {
        val b = PictureInPictureParams.Builder().setAspectRatio(pipRatio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(autoPip)
            b.setSeamlessResizeEnabled(true)
        }
        return b.build()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 8 a 11 : pas d'entree automatique, on la declenche ici.
        if (autoPip && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            try { enterPictureInPictureMode(pipParams()) } catch (_: Exception) {}
        }
    }

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
                                if (mcLock == null) mcLock = wm.createMulticastLock("Canalix:cast").apply {
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
        // Image dans l'image : bouton du lecteur, ou automatique en quittant l'app.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "streamflow/pip")
            .setMethodCallHandler { call, result ->
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    pipRatio = safeRatio(call.argument<Int>("w") ?: 16, call.argument<Int>("h") ?: 9)
                    when (call.method) {
                        "enter" -> result.success(enterPictureInPictureMode(pipParams()))
                        "auto" -> {
                            autoPip = call.argument<Boolean>("enabled") ?: false
                            setPictureInPictureParams(pipParams())
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.success(false)
                }
            }
    }
}
