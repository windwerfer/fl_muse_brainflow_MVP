use flutter_rust_bridge::frb;

pub const MUSE_GATT_ATTR_STREAM_TOGGLE: &str = "273e0001-4c4d-454d-96b4-4b455555494f";
pub const MUSE_GATT_ATTR_TP9: &str = "273e0002-4c4d-454d-96b4-4b455555494f";
pub const MUSE_GATT_ATTR_AF7: &str = "273e0003-4c4d-454d-96b4-4b455555494f";
pub const MUSE_GATT_ATTR_AF8: &str = "273e0004-4c4d-454d-96b4-4b455555494f";
pub const MUSE_GATT_ATTR_TP10: &str = "273e0005-4c4d-454d-96b4-4b455555494f";
pub const MUSE_GATT_ATTR_RIGHTAUX: &str = "273e0006-4c4d-454d-96b4-4b455555494f";
pub const MUSE_GATT_ATTR_ACCELEROMETER: &str = "273e0007-4c4d-454d-96b4-4b455555494f";
pub const MUSE_GATT_ATTR_GYRO: &str = "273e0008-4c4d-454d-96b4-4b455555494f";
pub const MUSE_GATT_ATTR_PPG0: &str = "273e0009-4c4d-454d-96b4-4b455555494f";
pub const MUSE_GATT_ATTR_PPG1: &str = "273e000a-4c4d-454d-96b4-4b455555494f";
pub const MUSE_GATT_ATTR_PPG2: &str = "273e000b-4c4d-454d-96b4-4b455555494f";

pub const MUSE_GYRO_SCALE_FACTOR: f64 = 0.06103515625;
pub const MUSE_ACCEL_SCALE_FACTOR: f64 = 0.00006103515635;
pub const EEG_SCALE: f64 = 125.0 / 256.0;
pub const EEG_OFFSET: f64 = 0x800 as f64;

#[frb]
#[derive(Debug, Clone, Default)]
pub struct MuseRawPacket {
    pub channel: u8,
    pub data: Vec<u8>,
}

#[frb]
#[derive(Debug, Clone, Default)]
pub struct MuseProcessedData {
    pub eeg: Vec<Vec<f64>>,
    pub ppg_ir: Vec<f64>,
    pub ppg_red: Vec<f64>,
    pub spo2: Option<f64>,
    pub accel: [f64; 3],
    pub gyro: [f64; 3],
    pub timestamp: f64,
    pub battery: f64,
    pub packet_types: Vec<MusePacketType>,
}

#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MusePacketType {
    #[frb(rename = "EegPpg")]
    EegPpg,
    #[frb(rename = "Imu")]
    Imu,
    Eeg,
    Ppg,
    Accel,
    Gyro,
    None,
    Other,
}

#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MuseModel {
    MuseS,
    Muse2,
    Muse2016,
    Unknown,
}

impl MuseModel {
    pub fn has_ppg(&self) -> bool {
        matches!(self, MuseModel::MuseS | MuseModel::Muse2)
    }
}
