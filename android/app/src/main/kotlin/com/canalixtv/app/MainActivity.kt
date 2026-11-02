package com.canalixtv.app

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Moteur partage avec le processus : il survit a la fermeture de l'ecran
    // pour que les enregistrements continuent.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        CanalixApp.engine(application)

    override fun shouldDestroyEngineWithHost(): Boolean = false


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
        // Le canal "streamflow/background" est enregistre par CanalixApp
        // (il doit marcher meme sans ecran ouvert).
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
