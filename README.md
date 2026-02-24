# fl_muse_brainflow_MVP

This is minimal flutter implementation for the brainflow lib for Linux and Android (possibly Windows later, no Mac/iOS because i dont have the hardware). Muse S and Muse 2 will be the only tested devices (since thats what i have). Its goal is to be a base / sample code for cross platform EEG tools (biofeedback / logging ..). 

# Goal?

You clone the code, compile it, and it just runs. You add whatever you need.

# Why?

I wanted to do some simple Biofeedback tests and couldnt find anything for the mobile platforms. the brainflow lib is a awesome toolkit, but it is beyond me to get the bluetooth to work on android. so this project uses the Flutter Bluetooth BLE lib to do the connection to Muse and then passes that data to brainflow for the real number crunching.

# Codeing

Its Flutter/Dart (UI, Bluetooth connections, Graphs..) with Rust (processing the EEG Signals). Rust because I dont have the confidence to write the complex streaming logic without some buffer overflows.


## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
