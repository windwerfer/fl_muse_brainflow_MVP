pub mod api;
mod frb_generated;

#[cfg(target_os = "android")]
mod android_jni;

#[cfg(target_os = "android")]
pub use android_jni::{
    JNI_OnLoad, Java_com_windwerfer_fl_1muse_1brainflow_1mvp_MainActivity_initBrainFlow,
};

// Muse S specific modules (app logic, not BrainFlow)
mod muse_parser;
mod muse_types;

pub use muse_parser::*;
pub use muse_types::*;
