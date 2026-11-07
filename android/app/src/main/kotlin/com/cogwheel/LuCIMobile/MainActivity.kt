package com.cogwheel.LuCIMobile

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import android.os.Build

// FragmentActivity: local_auth's BiometricPrompt needs a fragment host.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Enable edge-to-edge display without using deprecated APIs
        setupEdgeToEdge()
    }
    
    private fun setupEdgeToEdge() {
        // Enable edge-to-edge layout
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        // Use WindowInsetsController instead of deprecated window flags
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller?.let {
            // Make status bar and navigation bar transparent without deprecated APIs
            it.isAppearanceLightStatusBars = false
            it.isAppearanceLightNavigationBars = false
        }
        
        // For Android 15+ (API 35+), use the modern EdgeToEdge API
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            enableModernEdgeToEdge()
        }
    }
    
    private fun enableModernEdgeToEdge() {
        try {
            // Use reflection to call EdgeToEdge.enable() for Android 15+
            val edgeToEdgeClass = Class.forName("androidx.activity.EdgeToEdge")
            val enableMethod = edgeToEdgeClass.getMethod("enable", androidx.activity.ComponentActivity::class.java)
            enableMethod.invoke(null, this)
        } catch (e: Exception) {
            // Fallback is already handled by setupEdgeToEdge()
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Edge-to-edge is now handled natively without intercepting Flutter calls
        // This prevents deprecated API usage while maintaining compatibility
    }
}
