package ai.ailigent.hermes_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/** Persistent remote messaging session, analogous to a terminal's foreground service.
 * Does not pretend to be cloud push: force-stop/process death ends delivery.
 */
class GatewayService : Service() {
    companion object {
        const val ID = 9131
        const val CHANNEL = "gateway_connection"
        const val STOP = "ai.ailigent.hermes_mobile.STOP_BACKGROUND"
        private var instance: GatewayService? = null
        val running: Boolean get() = instance != null
        fun update(status: String) { instance?.setStatus(status) }
    }
    private var wakeLock: PowerManager.WakeLock? = null
    private var status = "جارٍ الاتصال بالخادم"

    override fun onCreate() {
        super.onCreate()
        instance = this
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(CHANNEL,
            "اتصال Hermes في الخلفية", NotificationManager.IMPORTANCE_LOW).apply {
            description = "يحافظ على اتصال المحادثة أثناء استخدام تطبيقات أخرى"
            setShowBadge(false)
        })
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
        } else {
            startForeground(ID, notification())
        }
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Hermes:Gateway").apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) stopSelf()
        // Restarting without the authenticated Dart engine would be misleading.
        // Android force-stop requires explicit relaunch; do not secretly restart.
        return START_NOT_STICKY
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, GatewayService::class.java).setAction(STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Hermes يعمل في الخلفية")
            .setContentText(status)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .addAction(Notification.Action.Builder(null, "إيقاف الخلفية", stop).build())
            .build()
    }

    private fun setStatus(value: String) {
        if (status == value) return
        status = value
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(ID, notification())
    }

    override fun onDestroy() {
        instance = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        (application as HermesApplication).serviceStopped()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
