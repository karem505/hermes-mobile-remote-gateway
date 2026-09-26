package ai.ailigent.hermes_mobile

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun provideFlutterEngine(context: android.content.Context): io.flutter.embedding.engine.FlutterEngine =
        (application as HermesApplication).getEngine()

    override fun shouldDestroyEngineWithHost(): Boolean = false
}
