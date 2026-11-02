package com.canalixtv.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Reveille l'appareil a l'heure d'un enregistrement prevu, meme si l'app
 * est fermee ou l'ecran eteint, et apres un redemarrage.
 */
object RecordingAlarm {
    private const val PREFS = "canalix_recording_alarm"
    private const val KEY = "next_ms"
    private const val KEY_TITLE = "title"

    fun canExact(ctx: Context): Boolean {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
    }

    /** Programme le reveil (0 = aucun enregistrement prevu). */
    fun set(ctx: Context, atMs: Long, title: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(KEY, atMs).putString(KEY_TITLE, title).apply()
        schedule(ctx)
    }

    fun schedule(ctx: Context) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val at = p.getLong(KEY, 0)
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            ctx, 1, Intent(ctx, AlarmReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        am.cancel(pi)
        if (at <= System.currentTimeMillis()) return
        // Une minute d'avance : le temps de demarrer et de se connecter.
        val wake = at - 60_000
        try {
            if (canExact(ctx)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, wake, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, wake, pi)
            }
        } catch (_: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, wake, pi)
        }
    }

    fun title(ctx: Context): String =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TITLE, "") ?: ""
}

/** L'heure est venue : demarre le service, qui garde le code Dart en vie. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val i = Intent(ctx, RecordingService::class.java)
            .putExtra("title", "Canalix")
            .putExtra("text", RecordingAlarm.title(ctx))
            .putExtra("active", true)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i)
            else ctx.startService(i)
        } catch (_: Exception) {}
        // Le moteur Dart demarre avec le processus (CanalixApp) et lance l'enregistrement.
        (ctx.applicationContext as? android.app.Application)?.let { CanalixApp.engine(it) }
    }
}

/** Apres un redemarrage de l'appareil : on reprogramme le reveil. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        RecordingAlarm.schedule(ctx)
    }
}
