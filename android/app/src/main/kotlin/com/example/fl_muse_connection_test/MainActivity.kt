package com.example.fl_muse_connection_test

import io.flutter.embedding.android.FlutterActivity
import android.content.Context
import android.os.Bundle
import android.util.Log

class MainActivity : FlutterActivity() {
    companion object {
        init {
            try {
                Log.i("MuseStream", "Loading native BrainFlow dependencies...")
                System.loadLibrary("usb1.0")
                System.loadLibrary("ftdi1")
                System.loadLibrary("BoardController")
                System.loadLibrary("DataHandler")
                System.loadLibrary("MLModule")
                System.loadLibrary("rust_lib_muse_stream") // Load our Rust bridge
                Log.i("MuseStream", "All native libraries loaded successfully.")
            } catch (e: Exception) {
                Log.e("MuseStream", "Error loading native libraries: ${e.message}")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            Log.i("MuseStream", "Calling Rust initBrainFlow(context)...")
            initBrainFlow(this.applicationContext)
            Log.i("MuseStream", "Rust initBrainFlow returned.")
        } catch (e: Exception) {
            Log.e("MuseStream", "Failed to call initBrainFlow: ${e.message}")
            e.printStackTrace()
        }
    }

    external fun initBrainFlow(context: Context)
}
