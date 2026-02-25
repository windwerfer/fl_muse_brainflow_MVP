use crate::muse_types::{
    MuseModel, MusePacketType, MuseProcessedData, EEG_OFFSET, EEG_SCALE, MUSE_ACCEL_SCALE_FACTOR,
    MUSE_GYRO_SCALE_FACTOR,
};
use flutter_rust_bridge::frb;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

static MUSE_STATE: Mutex<Option<MuseState>> = Mutex::new(None);

struct MuseState {
    model: MuseModel,
    eeg_buffers: [Vec<f64>; 5],
    accel_buffer: [f64; 3],
    gyro_buffer: [f64; 3],
    ppg_buffer: [Vec<f64>; 3],
    received_channels: [bool; 5],
    last_timestamp: f64,
    package_count: u16,
    initialized: bool,
}

impl MuseState {
    fn new() -> Self {
        Self {
            model: MuseModel::Unknown,
            eeg_buffers: [
                const { Vec::new() },
                const { Vec::new() },
                const { Vec::new() },
                const { Vec::new() },
                const { Vec::new() },
            ],
            accel_buffer: [0.0; 3],
            gyro_buffer: [0.0; 3],
            ppg_buffer: [
                const { Vec::new() },
                const { Vec::new() },
                const { Vec::new() },
            ],
            received_channels: [false; 5],
            last_timestamp: 0.0,
            package_count: 0,
            initialized: false,
        }
    }
}

fn get_timestamp() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs_f64()
}

#[frb]
pub fn init_muse_parser(model: MuseModel) {
    let mut state = MUSE_STATE.lock().unwrap();
    let mut muse_state = MuseState::new();
    muse_state.model = model;
    muse_state.initialized = true;
    *state = Some(muse_state);
}

#[frb]
pub fn parse_muse_packet(channel: i32, data: Vec<u8>) -> Vec<MuseProcessedData> {
    let mut results = Vec::new();

    {
        let mut state = MUSE_STATE.lock().unwrap();
        if state.is_none() {
            let mut muse_state = MuseState::new();
            muse_state.model = MuseModel::MuseS;
            muse_state.initialized = true;
            *state = Some(muse_state);
        }
    }

    let mut state = MUSE_STATE.lock().unwrap();
    let muse_state = state.as_mut().unwrap();

    if data.len() != 20 {
        return results;
    }

    match channel {
        0..=4 => {
            if let Some(data) = parse_eeg_channel(muse_state, channel as usize, &data) {
                results.push(data);
            }
        }
        5 => {
            if let Some(data) = parse_accel_data(muse_state, &data) {
                results.push(data);
            }
        }
        6 => {
            if let Some(data) = parse_gyro_data(muse_state, &data) {
                results.push(data);
            }
        }
        7..=9 => {
            if let Some(data) = parse_ppg_channel(muse_state, channel as usize - 7, &data) {
                results.push(data);
            }
        }
        _ => {}
    }

    results
}

fn parse_eeg_channel(
    state: &mut MuseState,
    channel: usize,
    data: &[u8],
) -> Option<MuseProcessedData> {
    if channel >= 5 {
        return None;
    }

    let package_num = ((data[0] as u16) << 8) | (data[1] as u16);
    state.package_count = package_num;

    let samples = parse_eeg_samples(&data[2..]);
    state.eeg_buffers[channel].extend(samples);
    state.received_channels[channel] = true;

    let all_received = state.received_channels.iter().filter(|&&x| x).count();
    let required = if channel == 4 { 4 } else { 5 };

    if all_received >= required {
        let result = MuseProcessedData {
            eeg: state.eeg_buffers.iter().map(|v| v.clone()).collect(),
            ppg_ir: vec![],
            ppg_red: vec![],
            spo2: None,
            accel: state.accel_buffer,
            gyro: state.gyro_buffer,
            timestamp: get_timestamp(),
            battery: 0.0,
            packet_types: vec![MusePacketType::Eeg],
        };

        for buf in &mut state.eeg_buffers {
            buf.clear();
        }
        state.received_channels = [false; 5];

        Some(result)
    } else {
        None
    }
}

fn parse_eeg_samples(data: &[u8]) -> Vec<f64> {
    let mut samples = Vec::with_capacity(12);
    for i in (0..data.len()).step_by(3) {
        if i + 2 < data.len() {
            let val1 = ((data[i] as u16) << 4) | ((data[i + 1] >> 4) as u16);
            let val2 = (((data[i + 1] & 0x0F) as u16) << 8) | (data[i + 2] as u16);

            let scaled1 = ((val1 as f64) - EEG_OFFSET) * EEG_SCALE;
            let scaled2 = ((val2 as f64) - EEG_OFFSET) * EEG_SCALE;
            samples.push(scaled1);
            samples.push(scaled2);
        }
    }
    samples
}

fn parse_accel_data(state: &mut MuseState, data: &[u8]) -> Option<MuseProcessedData> {
    for i in 0..3 {
        let offset = 2 + i * 6;
        if offset + 5 < data.len() {
            let x = cast_16bit_to_int32(&data[offset..]) as f64 * MUSE_ACCEL_SCALE_FACTOR;
            let y = cast_16bit_to_int32(&data[offset + 2..]) as f64 * MUSE_ACCEL_SCALE_FACTOR;
            let z = cast_16bit_to_int32(&data[offset + 4..]) as f64 * MUSE_ACCEL_SCALE_FACTOR;
            state.accel_buffer = [x, y, z];
        }
    }

    Some(MuseProcessedData {
        eeg: vec![],
        ppg_ir: vec![],
        ppg_red: vec![],
        spo2: None,
        accel: state.accel_buffer,
        gyro: [0.0; 3],
        timestamp: get_timestamp(),
        battery: 0.0,
        packet_types: vec![MusePacketType::Accel],
    })
}

fn parse_gyro_data(state: &mut MuseState, data: &[u8]) -> Option<MuseProcessedData> {
    for i in 0..3 {
        let offset = 2 + i * 6;
        if offset + 5 < data.len() {
            let x = cast_16bit_to_int32(&data[offset..]) as f64 * MUSE_GYRO_SCALE_FACTOR;
            let y = cast_16bit_to_int32(&data[offset + 2..]) as f64 * MUSE_GYRO_SCALE_FACTOR;
            let z = cast_16bit_to_int32(&data[offset + 4..]) as f64 * MUSE_GYRO_SCALE_FACTOR;
            state.gyro_buffer = [x, y, z];
        }
    }

    Some(MuseProcessedData {
        eeg: vec![],
        ppg_ir: vec![],
        ppg_red: vec![],
        spo2: None,
        accel: [0.0; 3],
        gyro: state.gyro_buffer,
        timestamp: get_timestamp(),
        battery: 0.0,
        packet_types: vec![MusePacketType::Gyro],
    })
}

fn parse_ppg_channel(
    state: &mut MuseState,
    ppg_idx: usize,
    data: &[u8],
) -> Option<MuseProcessedData> {
    if ppg_idx >= 3 || !state.model.has_ppg() {
        return None;
    }

    let ppg_values = parse_ppg_samples(&data[2..]);
    state.ppg_buffer[ppg_idx] = ppg_values;

    let has_ppg = state.ppg_buffer.iter().filter(|v| !v.is_empty()).count() >= 2;

    if has_ppg {
        let ppg_ir = state.ppg_buffer[0].clone();
        let ppg_red = state.ppg_buffer[1].clone();
        let spo2 = calculate_spo2(&ppg_ir, &ppg_red);

        for buf in &mut state.ppg_buffer {
            buf.clear();
        }

        Some(MuseProcessedData {
            eeg: vec![],
            ppg_ir,
            ppg_red,
            spo2,
            accel: [0.0; 3],
            gyro: [0.0; 3],
            timestamp: get_timestamp(),
            battery: 0.0,
            packet_types: vec![MusePacketType::Ppg],
        })
    } else {
        None
    }
}

fn parse_ppg_samples(data: &[u8]) -> Vec<f64> {
    let mut samples = Vec::with_capacity(6);
    for i in (0..data.len()).step_by(3) {
        if i + 2 < data.len() {
            let val = cast_24bit_to_int32(&data[i..]) as f64;
            samples.push(val);
        }
    }
    samples
}

fn cast_16bit_to_int32(data: &[u8]) -> i32 {
    let val = ((data[0] as u16) << 8) | (data[1] as u16);
    if val & 0x8000 != 0 {
        (val as i32) - 0x10000
    } else {
        val as i32
    }
}

fn cast_24bit_to_int32(data: &[u8]) -> i32 {
    let val = ((data[0] as u32) << 16) | ((data[1] as u32) << 8) | (data[2] as u32);
    if val & 0x800000 != 0 {
        (val as i32) - 0x1000000
    } else {
        val as i32
    }
}

fn calculate_spo2(ppg_ir: &[f64], ppg_red: &[f64]) -> Option<f64> {
    if ppg_ir.len() < 32 || ppg_red.len() < 32 {
        return None;
    }

    let ir_mean: f64 = ppg_ir.iter().sum::<f64>() / ppg_ir.len() as f64;
    let red_mean: f64 = ppg_red.iter().sum::<f64>() / ppg_red.len() as f64;

    if ir_mean <= 0.0 || red_mean <= 0.0 {
        return None;
    }

    let ratio = red_mean / ir_mean;
    let spo2 = 110.0 - 25.0 * ratio;

    Some(spo2.clamp(0.0, 100.0))
}

#[frb]
pub fn send_muse_command(command: &str) -> Vec<u8> {
    let cmd_bytes = command.as_bytes();
    let mut packet = vec![(cmd_bytes.len() + 1) as u8];
    packet.extend_from_slice(cmd_bytes);
    packet.push(10);
    packet
}

#[frb]
pub fn get_muse_model_from_name(name: &str) -> MuseModel {
    let name_lower = name.to_lowercase();
    if name_lower.contains("muse s") || name_lower.contains("muse-s") {
        MuseModel::MuseS
    } else if name_lower.contains("muse 2") || name_lower.contains("muse2") {
        MuseModel::Muse2
    } else if name_lower.contains("muse 2016") || name_lower.contains("muse-2016") {
        MuseModel::Muse2016
    } else {
        MuseModel::Unknown
    }
}

#[frb]
pub fn parse_and_process_muse_packets(raw_packets: Vec<Vec<u8>>) -> Vec<MuseProcessedData> {
    let mut results = Vec::new();
    for (i, packet) in raw_packets.into_iter().enumerate() {
        let mut parsed = parse_muse_packet(i as i32, packet);
        results.append(&mut parsed);
    }
    if results.is_empty() {
        results.push(MuseProcessedData {
            eeg: vec![vec![0.0; 12]; 5],
            ppg_ir: vec![],
            ppg_red: vec![],
            spo2: None,
            accel: [0.0; 3],
            gyro: [0.0; 3],
            timestamp: get_timestamp(),
            battery: 0.0,
            packet_types: vec![MusePacketType::Eeg],
        });
    }
    results
}
