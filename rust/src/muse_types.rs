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

#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EegResolution {
    Bits12,
    Bits14,
}

impl EegResolution {
    pub fn scale_factor(&self) -> f64 {
        match self {
            EegResolution::Bits12 => 125.0 / 256.0,
            EegResolution::Bits14 => 125.0 / 2048.0,
        }
    }

    pub fn offset(&self) -> f64 {
        match self {
            EegResolution::Bits12 => 0x800 as f64,
            EegResolution::Bits14 => 0x2000 as f64,
        }
    }
}

#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MuseModel {
    Muse2016,
    Muse2,
    MuseS,
    MuseSAthena,
    Unknown,
}

impl MuseModel {
    pub fn channel_count(&self) -> usize {
        match self {
            MuseModel::Muse2016 => 4,
            MuseModel::Muse2 => 4,
            MuseModel::MuseS => 5,
            MuseModel::MuseSAthena => 7,
            MuseModel::Unknown => 4,
        }
    }

    pub fn resolution(&self) -> EegResolution {
        match self {
            MuseModel::MuseSAthena => EegResolution::Bits14,
            _ => EegResolution::Bits12,
        }
    }

    pub fn has_ppg(&self) -> bool {
        matches!(
            self,
            MuseModel::Muse2 | MuseModel::MuseS | MuseModel::MuseSAthena
        )
    }

    pub fn has_fnirs(&self) -> bool {
        matches!(self, MuseModel::MuseSAthena)
    }

    pub fn ppg_channel_count(&self) -> usize {
        match self {
            MuseModel::Muse2 | MuseModel::MuseS => 2,
            MuseModel::MuseSAthena => 3,
            _ => 0,
        }
    }
}

#[frb]
#[derive(Debug, Clone, Default)]
pub struct MuseProcessedData {
    pub eeg: Vec<Vec<f64>>,
    pub ppg_ir: Vec<f64>,
    pub ppg_red: Vec<f64>,
    pub ppg_nir: Vec<f64>,
    pub spo2: Option<f64>,
    pub fnirs_hbo2: Option<f64>,
    pub fnirs_hbr: Option<f64>,
    pub fnirs_tsi: Option<f64>,
    pub accel: [f64; 3],
    pub gyro: [f64; 3],
    pub timestamp: f64,
    pub battery: f64,
    pub packet_types: Vec<MusePacketType>,
    pub signal_quality: f64,
    pub mindfulness: Option<f64>,
    pub restfulness: Option<f64>,
    pub alpha: Option<f64>,
    pub beta: Option<f64>,
    pub gamma: Option<f64>,
    pub delta: Option<f64>,
    pub theta: Option<f64>,
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
    Fnirs,
    Battery,
    None,
    Other,
}
