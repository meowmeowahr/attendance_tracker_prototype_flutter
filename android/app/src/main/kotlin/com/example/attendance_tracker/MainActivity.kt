package com.example.attendance_tracker

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Disable Android default focus highlight for the root view
        window?.decorView?.rootView?.defaultFocusHighlightEnabled = false
    }
}
