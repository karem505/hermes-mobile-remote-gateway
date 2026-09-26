package ai.ailigent.hermes_mobile

import android.app.Application
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.net.Uri
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** One engine owns one gateway even when the Activity is removed from recents. */
class HermesApplication : Application() {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    @Synchronized
    fun getEngine(): FlutterEngine {
        engine?.let { return it }
        val created = FlutterEngine(this)
        engine = created
        channel = MethodChannel(created.dartExecutor.binaryMessenger, "hermes/background")
        channel!!.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, GatewayService::class.java)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        observeNetwork()
                        result.success(null)
                    }
                    "update" -> {
                        GatewayService.update(call.argument<String>("status") ?: "متصل")
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, GatewayService::class.java))
                        stopObservingNetwork()
                        result.success(null)
                    }
                    "status" -> {
                        val power = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(mapOf("running" to GatewayService.running,
                            "batteryExempt" to power.isIgnoringBatteryOptimizations(packageName)))
                    }
                    "batterySettings" -> {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("background_service", e.message, null)
            }
        }
        created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return created
    }

    private fun observeNetwork() {
        if (networkCallback != null) return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                handler.post { channel?.invokeMethod("networkAvailable", null) }
            }
        }
        networkCallback = callback
        (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).registerDefaultNetworkCallback(callback)
    }

    private fun stopObservingNetwork() {
        networkCallback?.let {
            (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(it)
        }
        networkCallback = null
    }

    fun serviceStopped() {
        stopObservingNetwork()
        channel?.invokeMethod("stopped", null)
    }
}
