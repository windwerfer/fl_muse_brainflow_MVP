use std::env;
use std::path::PathBuf;

fn main() {
    let project_root = env::var("CARGO_MANIFEST_DIR").unwrap();
    let project_root = PathBuf::from(project_root).parent().unwrap().to_path_buf();
    
    let target = env::var("TARGET").unwrap();
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();
    
    if target.contains("android") {
        println!("cargo:warning=Android target - using runtime symbol lookup (skipping compile-time linking)");
        return;
    }

    let lib_dir = match target_os.as_str() {
        "linux" => project_root.join("packages").join("brainflow").join("lib").join("linux"),
        "windows" => project_root.join("packages").join("brainflow").join("lib").join("windows"),
        _ => panic!("Unsupported target OS: {}", target_os),
    };

    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    
    // Link the core brainflow libraries
    println!("cargo:rustc-link-lib=dylib=BoardController");
    println!("cargo:rustc-link-lib=dylib=DataHandler");
    println!("cargo:rustc-link-lib=dylib=MLModule");

    // For Linux, we often need to set rpath so the executable finds the .so files
    if target_os == "linux" {
        println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN");
    }
}
