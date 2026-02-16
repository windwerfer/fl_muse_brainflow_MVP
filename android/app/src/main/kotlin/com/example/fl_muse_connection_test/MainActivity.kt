package com.example.fl_muse_connection_test

import brainflow.BrainFlowApi
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

                // needed, or brainflow will not know that we run android and attempt to load the desktop rust_lib_muse_stream
                //    -> [error] failed to load lib
                BrainFlowApi.setJniEnv()
            } catch (e: Exception) {
                Log.e("MuseStream", "Error loading native libraries: ${e.message}")
            }
        }
    }
}
