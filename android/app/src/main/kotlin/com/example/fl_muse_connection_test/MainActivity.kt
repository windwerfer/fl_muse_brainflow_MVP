package com.example.fl_muse_brainflow_MVP

import io.flutter.embedding.android.FlutterActivity
import android.content.Context
import android.os.Bundle
import android.util.Log

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            Log.i("MuseStream", "Initializing BrainFlow JNI...")
            initBrainFlow(this.applicationContext)
            Log.i("MuseStream", "BrainFlow JNI init called.")
        } catch (e: Exception) {
            Log.e("MuseStream", "Error initializing BrainFlow JNI: ${e.message}")
        }
    }

    companion object {
        @JvmStatic
        private external fun initBrainFlow(context: Context)

        init {
            try {
                Log.i("MuseStream", "Loading native BrainFlow dependencies...")
                System.loadLibrary("BoardController")
                System.loadLibrary("DataHandler")

                // --- maybe not needed
                // System.loadLibrary("usb1.0")
                // System.loadLibrary("ftdi1")
                System.loadLibrary("MLModule")


                // ML optional: System.loadLibrary("MLModule")
                System.loadLibrary("rust_lib_muse_stream") // Your Rust bridge
                Log.i("MuseStream", "All native libraries loaded successfully.")
            } catch (e: Exception) {
                Log.e("MuseStream", "Error loading native libraries: ${e.message}")
            }
        }
    }
}
