package com.pharmashelf.app

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity extends ComponentActivity so enableEdgeToEdge() is
// available (FlutterActivity extends Activity only). Recommended for targetSdk 35 / Android 15.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            window.attributes =
                window.attributes.apply {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                }
        }
        super.onCreate(savedInstanceState)
    }
}
