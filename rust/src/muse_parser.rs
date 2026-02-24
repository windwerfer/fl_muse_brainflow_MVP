use crate::muse_types::{MusePacketType, MuseProcessedData};
use chrono::Utc;
use flutter_rust_bridge::frb;

#[frb]
pub fn parse_and_process_muse_packets(raw_packets: Vec<Vec<u8>>) -> Vec<MuseProcessedData> {
    let mut results = Vec::new();

    for packet in raw_packets {
        if packet.len() < 2 {
            continue;
        }

        match packet[0] {
            0xDF => {
                let (raw_eeg, ppg_ir, ppg_red) = unpack_eeg_ppg_packet(&packet);

                // TODO: replace with real BrainFlow processing (DataFilter::perform_bandpass + get_oxygen_level)
                let scaled_eeg = raw_eeg; // temporary pass-through

                let spo2 = if ppg_ir.len() >= 32 { Some(97.5) } else { None };

                results.push(MuseProcessedData {
                    eeg: scaled_eeg,
                    ppg_ir,
                    ppg_red,
                    spo2,
                    accel: [0.0; 3],
                    gyro: [0.0; 3],
                    timestamp: Utc::now().timestamp_millis() as f64 / 1000.0,
                    battery: 98.0,
                    packet_types: vec![MusePacketType::EegPpg],
                });
            }
            0xF4 => {
                let (ax, ay, az, gx, gy, gz) = unpack_imu_packet(&packet);
                results.push(MuseProcessedData {
                    eeg: vec![],
                    ppg_ir: vec![],
                    ppg_red: vec![],
                    spo2: None,
                    accel: [ax, ay, az],
                    gyro: [gx, gy, gz],
                    timestamp: Utc::now().timestamp_millis() as f64 / 1000.0,
                    battery: 98.0,
                    packet_types: vec![MusePacketType::Imu],
                });
            }
            _ => {}
        }
    }
    results
}

// ================== REPLACE WITH YOUR REAL UNPACKING LOGIC ==================
fn unpack_eeg_ppg_packet(_packet: &[u8]) -> (Vec<Vec<f64>>, Vec<f64>, Vec<f64>) {
    // TODO: port your 12-bit EEG + dual-PPG unpack from muse_native.cpp / amused-py
    // For now returns dummy data so everything compiles
    (vec![vec![0.0; 10]; 7], vec![100.0; 10], vec![95.0; 10])
}

fn unpack_imu_packet(_packet: &[u8]) -> (f64, f64, f64, f64, f64, f64) {
    // TODO: parse 3× accel + 3× gyro
    (0.1, 0.2, 0.3, 0.5, -0.4, 1.1)
}
