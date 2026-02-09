package com.example.fl_muse_connection_test

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.util.Log

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            Log.i("MuseStream", "Loading native BrainFlow libraries...")
            System.loadLibrary("BoardController")
            System.loadLibrary("DataHandler")
            System.loadLibrary("MLModule")
            Log.i("MuseStream", "Native libraries loaded successfully.")
        } catch (e: Exception) {
            Log.e("MuseStream", "Error loading native libraries: ${e.message}")
        }
        super.onCreate(savedInstanceState)
    }
}
