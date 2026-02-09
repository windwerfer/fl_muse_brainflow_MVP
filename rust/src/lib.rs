pub mod api; 
mod frb_generated;

#[cfg(target_os = "android")]
use jni::JNIEnv;
#[cfg(target_os = "android")]
use jni::objects::{JClass, JObject};
#[cfg(target_os = "android")]
use std::ffi::c_void;

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_example_fl_1muse_1connection_1test_MainActivity_initBrainFlow(
    mut env: JNIEnv,
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

    // We can't use log::info! easily here if logger isn't init, but we can try println
    println!("[RustJNI] Calling java_set_jnienv with env={:?} ctx={:?}", env_ptr, ctx_ptr);
    
    unsafe {
        let res = java_set_jnienv(env_ptr, ctx_ptr);
        println!("[RustJNI] java_set_jnienv returned: {}", res);
    }
}