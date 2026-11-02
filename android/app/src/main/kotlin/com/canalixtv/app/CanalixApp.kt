package com.canalixtv.app

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Le moteur Flutter vit avec le processus, pas avec l'ecran : quand on
 * ferme l'app (ou qu'Android la lance seul pour un enregistrement), le code
 * Dart continue de tourner tant que le service d'enregistrement est actif.
 */
class CanalixApp : Application() {
    override fun onCreate() {
        super.onCreate()
        engine(this)
    }

    companion object {
        const val ENGINE = "canalix_main"

        private const val WIFI_SERVICE = android.content.Context.WIFI_SERVICE

        fun engine(app: Application): FlutterEngine {
            FlutterEngineCache.getInstance().get(ENGINE)?.let { return it }
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(app)
            loader.ensureInitializationComplete(app, null)
            val e = FlutterEngine(app)
            e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            FlutterEngineCache.getInstance().put(ENGINE, e)
            background(app, e)
            return e
        }

        private var mcLock: WifiManager.MulticastLock? = null

        /** Service d'enregistrement, reveils, espace disque : sans ecran. */
        private fun background(app: Application, e: FlutterEngine) {
            MethodChannel(e.dartExecutor.binaryMessenger, "streamflow/background")
                .setMethodCallHandler { call, result ->
                    val i = Intent(app, RecordingService::class.java)
                    try {
                        when (call.method) {
                            "start" -> {
                                i.putExtra("title", call.argument<String>("title"))
                                i.putExtra("text", call.argument<String>("text"))
                                i.putExtra("active", call.argument<Boolean>("active") ?: true)
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) app.startForegroundService(i)
                                else app.startService(i)
                                result.success(true)
                            }
                            "stop" -> { app.stopService(i); result.success(true) }
                            "alarm" -> {
                                val at = (call.argument<Number>("at") ?: 0).toLong()
                                RecordingAlarm.set(app, at, call.argument<String>("title") ?: "")
                                result.success(RecordingAlarm.canExact(app))
                            }
                            "home" -> {
                                RecordingAlarm.setHome(app, call.arguments as? Boolean == true)
                                result.success(true)
                            }
                            "canExact" -> result.success(RecordingAlarm.canExact(app))
                            "askExact" -> {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    app.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                        Uri.parse("package:" + app.packageName))
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                }
                                result.success(true)
                            }
                            "storage" -> {
                                val st = StatFs(call.argument<String>("path") ?: app.filesDir.path)
                                result.success(mapOf("free" to st.availableBytes, "total" to st.totalBytes))
                            }
                            "multicastLock" -> {
                                val wm = app.getSystemService(WIFI_SERVICE) as WifiManager
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
                    } catch (ex: Exception) {
                        result.success(false)
                    }
                }
        }
    }
}
