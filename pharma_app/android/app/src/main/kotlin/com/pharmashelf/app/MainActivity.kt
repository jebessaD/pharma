package com.pharmashelf.app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity extends ComponentActivity so enableEdgeToEdge() is
// available (FlutterActivity extends Activity only). Recommended for targetSdk 35 / Android 15.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }
}
