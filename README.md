# flutter_muse_brainflow_MVP

This is *will be* a minimal flutter implementation for the brainflow lib for Linux and Android (possibly Windows later, no Mac/iOS because i dont have the hardware). Muse S and Muse 2 will be the only tested devices (since thats what i have). Its goal is to be a base / sample code for cross platform EEG tools (biofeedback / logging ..). 

**this is a work in progress at the moment.. will definatly break**
**come back next week and it should compile**

# Devices

                 tested     implemented   reimplemented from
Muse 2016                        x           (brainflow)
Muse 2                           x           (brainflow)
Muse S                           x           (brainflow)
Muse S Athena                    x           (amuse)


# Goal?

You clone the code, compile it, and it just runs. You add whatever you need.

# Why?

I wanted to do some simple Biofeedback tests and couldnt find anything for the mobile platforms. the brainflow lib is a awesome toolkit, but it is beyond me to get the bluetooth to work on android. so this project uses the Flutter Bluetooth BLE lib to do the connection to Muse and then passes that data to brainflow for the real number crunching.

# Codeing

Its Flutter/Dart (UI, Bluetooth connections, Graphs..) with Rust (processing the EEG Signals). Rust because I dont have the confidence to write the complex streaming logic without some buffer overflows.

# running under Linux

linux is the only platform that is a bit tricky.
You must install the bluez package and expose to the user:
```
sudo apt install bluez
sudo usermod -aG bluetooth $USER   # then reboot
```

test if it worked
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


Install git and rust [https://rustup.rs/] and flutter to run this on linux/win. For Android you also need Java JDK (17 or 21) and Android SDK + Command Line Tools (this is easiest through Android Studio). 

```bash
git clone https://github.com/windwerfer/fl_muse_brainflow_MVP.git

cargo install just
cargo install flutter_rust_bridge_codegen --force
```

test if everything is there (its just a small script that checks if all tools are available)
```bash
just doctor
```

first run
```bash
# for android:
just acc

# for linux:
just lcc
```

commands to rebuild/run normally
```bash
just a          # normal run  for Android
just ac         # clean + Android
just acc        # super-clean + Android   ← most used when something is broken

just l          # normal run  for Linux
just lc
just lcc

just f          # regenerate bindings only (included in acc & lcc)
```
