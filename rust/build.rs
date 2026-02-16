use std::env;
use std::path::PathBuf;

fn main() {
    let project_root = env::var("CARGO_MANIFEST_DIR").unwrap();
    let project_root = PathBuf::from(project_root).parent().unwrap().to_path_buf();
    
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();
    
    let lib_dir = match target_os.as_str() {
        "linux" => project_root.join("packages").join("brainflow").join("lib").join("linux"),
        "windows" => project_root.join("packages").join("brainflow").join("lib").join("windows"),
        "android" => {
            let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();
            let arch_dir = match target_arch.as_str() {
                "aarch64" => "arm64-v8a",
                "arm" => "armeabi-v7a",
                _ => panic!("Unsupported Android architecture: {}", target_arch),
            };
            project_root.join("packages").join("brainflow").join("lib").join("android").join(arch_dir)
        }
        _ => panic!("Unsupported target OS: {}", target_os),
    };

    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    
    // Link the core brainflow libraries
    println!("cargo:rustc-link-lib=dylib=BoardController");
    println!("cargo:rustc-link-lib=dylib=DataHandler");
    println!("cargo:rustc-link-lib=dylib=MLModule");

    if target_os == "android" {
        println!("cargo:rustc-link-lib=dylib=ftdi1");
        println!("cargo:rustc-link-lib=dylib=usb1.0");
    }

    // For Linux, we often need to set rpath so the executable finds the .so files
    if target_os == "linux" {
        println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN");
    }
}