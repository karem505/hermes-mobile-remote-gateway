package ai.ailigent.hermes_mobile

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun provideFlutterEngine(context: android.content.Context): io.flutter.embedding.engine.FlutterEngine =
        (application as HermesApplication).getEngine()

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestPeakRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        // Some OEM skins (ColorOS) reset the window mode when the app returns.
        requestPeakRefreshRate()
    }

    /**
     * Ask for the display's fastest mode at the current resolution (120 Hz on
     * most current phones). Without this the window reports no preference and
     * the system is free to run the app at 60 or 90 Hz. The system can still
     * lower it (battery saver, thermal), which is the right behaviour.
     */
    private fun requestPeakRefreshRate() {
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
        else @Suppress("DEPRECATION") windowManager.defaultDisplay
        display ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        val attrs = window.attributes
        if (attrs.preferredDisplayModeId == best.modeId) return
        attrs.preferredDisplayModeId = best.modeId
        window.attributes = attrs
    }
}
