use flutter_rust_bridge::frb;

#[frb]
#[derive(Debug, Clone, Default)]
pub struct MuseProcessedData {
    /// 7 channels × samples (in µV after BrainFlow scaling)
    pub eeg: Vec<Vec<f64>>,
    /// Infrared PPG (for HR + SpO2)
    pub ppg_ir: Vec<f64>,
    /// Red PPG
    pub ppg_red: Vec<f64>,
    /// Calculated SpO2 (null until enough samples)
    pub spo2: Option<f64>,
    /// Accelerometer [x, y, z] in g
    pub accel: [f64; 3],
    /// Gyroscope [x, y, z] in deg/s
    pub gyro: [f64; 3],
    /// Corrected timestamp (seconds since UNIX epoch)
    pub timestamp: f64,
    /// Battery % (0-100)
    pub battery: f64,
    /// Which packet types were in this batch
    pub packet_types: Vec<MusePacketType>,
}

#[frb]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MusePacketType {
    EegPpg = 0xDF,
    Imu = 0xF4,
    Other = 0x00,
}
