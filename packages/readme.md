extract https://github.com/brainflow-dev/brainflow/releases/download/5.20.1/jniLibs.zip for android libs and https://github.com/brainflow-dev/brainflow/releases/download/5.20.1/compiled_libs.tar for win/linux/mac libs

the android so files are stripped (to reduce size from 90mb to 10mb):

cd ~/dev/fl_muse_brainflow_MVP/a_libs/android/jniLibs/arm64-v8a-stripped
 ~/.android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip --strip-all  libBoardController.so  libDataHandler.so  libftdi1.so  libjnidispatch.so  libMLModule.so  libusb1.0.so