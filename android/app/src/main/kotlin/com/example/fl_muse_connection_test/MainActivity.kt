package com.example.fl_muse_connection_test

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.util.Log

class MainActivity : FlutterActivity() {
    
    // Declare the native method from libBoardController.so
    private external fun set_jnienv(env: Any): Int

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            Log.i("MuseStream", "Loading native BrainFlow libraries...")
            System.loadLibrary("BoardController")
            System.loadLibrary("DataHandler")
            System.loadLibrary("MLModule")
            
            // Set the JNI environment for BrainFlow
            // In BrainFlow's C++ code, this is expected to be called to initialize BLE
            // The method name in C++ is Java_org_brainflow_boardcontroller_BoardController_set_jnienv
            // But since we are calling it from our own class, we might need a wrapper or 
            // trust that the Rust side can handle it if we pass the env.
            Log.i("MuseStream", "Native libraries loaded successfully.")
        } catch (e: Exception) {
            Log.e("MuseStream", "Error loading native libraries: ${e.message}")
        }
        super.onCreate(savedInstanceState)
    }
}
