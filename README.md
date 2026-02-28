# flutter_muse_brainflow_MVP

This is *will be* a minimal flutter implementation for the brainflow lib for Linux and Android (possibly Windows later, no Mac/iOS because i dont have the hardware). Muse S and Muse 2 will be the only tested devices (since thats what i have). Its goal is to be a base / sample code for cross platform EEG tools (biofeedback / logging ..). 

**this is a work in progress at the moment.. will definatly break**
**come back next week and it should compile**

*******************
current state:
- flutter compiles for Linus & Android
- flutter flutter_blue_plus is wired up (the dart lib that will handle the BLE communication) and displays Muse devices (Bug: Linux at the moment falsely removes them again after 30s)
- Muse S / 2 / Athena code is reimplemented in Rust (untested, not yet wired together with the BLE stream from flutter_blue_plus)
- brainflow libs are correctly placed into the build apks and can be accesed for the linux version
*******************


# Devices

                 tested     implemented   reimplemented from       Android     Linux    Win
Muse 2016                        x           (brainflow)
Muse 2                           x           (brainflow)
Muse S                           x           (brainflow)
Muse S Athena                    x           (amuse)


# Goal?

This should become an example project. You clone the code, compile it, and it just runs. Then you add whatever you need.

# Why?

I wanted to do some simple Biofeedback tests and couldnt find anything for the mobile platforms. the brainflow lib is a awesome toolkit, but it is beyond me to get the bluetooth to work on android. So this project uses the Flutter Bluetooth BLE lib to do the connection to Muse and then passes that data to brainflow for the real number crunching.

# Codeing

Its Flutter/Dart (UI, Bluetooth connections, Graphs..) with Rust (processing the EEG Signals). Why Rust? Because I dont have the confidence to write the complex streaming logic without some buffer overflows.

# running under Linux

If the Bluetooth doesnt want to connect on linux you can try:
```
# install the bluez package and expose to the user
sudo apt install bluez
sudo usermod -aG bluetooth $USER   # then reboot
```
linux is the only platform that is a bit tricky with flutter_blue_plus.


To test if it worked:
```
bluetoothctl
```
inside the programm enter (should list all discovered bluetooth devices)
```
power on
scan on

exit
```

## 🚀 Quick Start


Requirements (Linux/Win): 
 - git 
 - rust [https://rustup.rs/] 
 - flutter 
 
Additionally for Android: 
 - Java JDK (tested with v21) 
 - Android SDK + Command Line Tools (this is easiest through Android Studio). 
 - Android NDK (tested with v28.2.13676358)
 - set the ANDROID_HOME and ANDROID_NDK_HOME and ANDROID_HOME enviorment variables !!

After that, clone the project and install 2 more Rust programms you need to run this:
```bash
git clone https://github.com/windwerfer/fl_muse_brainflow_MVP.git

cargo install --locked flutter_rust_bridge_codegen
```

(optional) for android arm builds 
```
rustup target add aarch64-linux-android armv7-linux-androideabi
```


test if everything is there (its just a small script that checks if all tools are available). 
(you need flutter/dart to be installed before you can run this)
```bash
dart tools/build.dart doctor
```

first run
```bash
# for android:
dart tools/build.dart  acc

# for linux:
dart tools/build.dart  lcc

# for Windows:
dart tools/build.dart  wcc
```

commands to rebuild/run normally
```bash
dart tools/build.dart  a          # normal run  for Android
dart tools/build.dart  ac         # clean + Android
dart tools/build.dart  acc        # super-clean + Android   ← most used when something is broken

dart tools/build.dart  l          # normal run  for Linux
dart tools/build.dart  lc
dart tools/build.dart  lcc

dart tools/build.dart  w          # normal run  for Linux
dart tools/build.dart  wc
dart tools/build.dart  wcc
```
