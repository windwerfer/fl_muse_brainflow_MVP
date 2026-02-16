use jni::objects::{JClass, JObject};
use jni::JNIEnv;
use jni::JavaVM;
use log::info;
use std::ffi::c_void;

#[no_mangle]
pub extern "system" fn JNI_OnLoad(vm: JavaVM, _reserved: *mut c_void) -> jni::sys::jint {
    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::Info)
            .with_tag("RustJNI"),
    );
    info!(
        "[JNI_OnLoad] Library loaded. Target OS: {}",
        std::env::consts::OS
    );

    let env = match vm.get_env() {
        Ok(env) => env,
        Err(e) => {
            log::error!("[JNI_OnLoad] Failed to get JNIEnv: {:?}", e);
            return jni::sys::JNI_ERR;
        }
    };

    extern "C" {
        fn java_set_jnienv(env: *mut c_void, context: *mut c_void) -> i32;
    }

    let env_ptr = env.get_native_interface() as *mut c_void;
    let ctx_ptr = std::ptr::null_mut();

    info!(
        "[JNI_OnLoad] Calling java_set_jnienv with env={:?} ctx=NULL",
        env_ptr
    );

    unsafe {
        let res = java_set_jnienv(env_ptr, ctx_ptr);
        info!("[JNI_OnLoad] java_set_jnienv returned: {}", res);
    }

    jni::sys::JNI_VERSION_1_6
}

// The Java callback function...
#[no_mangle]
pub extern "system" fn Java_com_example_fl_1muse_1connection_1test_MainActivity_initBrainFlow(
    env: JNIEnv,
    _class: JClass,
    context: JObject,
) {
    // Define the signature that BrainFlow C++ expects: (JNIEnv*, jobject)
    extern "C" {
        fn java_set_jnienv(env: *mut c_void, context: *mut c_void) -> i32;
    }

    // Get the raw pointers
    let env_ptr = env.get_native_interface() as *mut c_void;
    let ctx_ptr = context.as_raw() as *mut c_void;

    info!(
        "[RustJNI] Calling java_set_jnienv with env={:?} ctx={:?}",
        env_ptr, ctx_ptr
    );

    unsafe {
        let res = java_set_jnienv(env_ptr, ctx_ptr);
        info!("[RustJNI] java_set_jnienv returned: {}", res);
    }
}
