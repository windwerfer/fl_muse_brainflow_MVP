use crate::api;
use crate::muse_types::{
    EegResolution, MuseModel, MusePacketType, MuseProcessedData, MUSE_ACCEL_SCALE_FACTOR,
    MUSE_GYRO_SCALE_FACTOR,
};
use flutter_rust_bridge::frb;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

static MUSE_STATE: Mutex<Option<MuseState>> = Mutex::new(None);

const MAX_EEG_CHANNELS: usize = 7;
const MAX_PPG_CHANNELS: usize = 3;

struct MuseState {
    model: MuseModel,
    eeg_buffers: Vec<Vec<f64>>,
    accel_buffer: [f64; 3],
    gyro_buffer: [f64; 3],
    ppg_buffer: Vec<Vec<f64>>,
    received_eeg_channels: Vec<bool>,
    last_timestamp: f64,
    package_count: u16,
    initialized: bool,
}

impl MuseState {
    fn new(model: MuseModel) -> Self {
        let channel_count = model.channel_count();
        let ppg_count = model.ppg_channel_count();

        Self {
            model,
            eeg_buffers: vec![Vec::new(); MAX_EEG_CHANNELS],
            accel_buffer: [0.0; 3],
            gyro_buffer: [0.0; 3],
            ppg_buffer: vec![Vec::new(); MAX_PPG_CHANNELS],
            received_eeg_channels: vec![false; MAX_EEG_CHANNELS],
            last_timestamp: 0.0,
            package_count: 0,
            initialized: true,
        }
    }

    fn channel_count(&self) -> usize {
        self.model.channel_count()
    }

    fn ppg_channel_count(&self) -> usize {
        self.model.ppg_channel_count()
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
    *state = Some(MuseState::new(model));
}

#[frb]
pub fn parse_muse_packet(channel: i32, data: Vec<u8>) -> Vec<MuseProcessedData> {
    let mut results = Vec::new();

    {
        let mut state = MUSE_STATE.lock().unwrap();
        if state.is_none() {
            *state = Some(MuseState::new(MuseModel::MuseS));
        }
    }

    let mut state = MUSE_STATE.lock().unwrap();
    let muse_state = state.as_mut().unwrap();

    if data.len() != 20 {
        return results;
    }

    let channel_count = muse_state.channel_count();

    match channel {
        0..=6 if (channel as usize) < channel_count => {
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
            if let Some(data) = parse_ppg_data(muse_state, channel as usize - 7, &data) {
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
    let channel_count = state.channel_count();
    if channel >= channel_count {
        return None;
    }

    let package_num = ((data[0] as u16) << 8) | (data[1] as u16);
    state.package_count = package_num;

    let resolution = state.model.resolution();
    let samples = parse_eeg_samples(&data[2..], resolution);
    state.eeg_buffers[channel].extend(samples);
    state.received_eeg_channels[channel] = true;

    let active_channels: usize = state
        .received_eeg_channels
        .iter()
        .take(channel_count)
        .filter(|&&x| x)
        .count();

    let required = if channel_count == 4 { 4 } else { channel_count };

    if active_channels >= required {
        let eeg: Vec<Vec<f64>> = state
            .eeg_buffers
            .iter()
            .take(channel_count)
            .map(|v| v.clone())
            .collect();

        let all_eeg_flat: Vec<f64> = eeg.iter().flatten().copied().collect();

        let signal_quality = api::calculate_signal_quality(all_eeg_flat.clone(), 256);

        let mindfulness = api::predict_mindfulness(all_eeg_flat.clone(), 256);
        let restfulness = api::predict_restfulness(all_eeg_flat.clone(), 256);

        let band_powers = api::calculate_band_powers(all_eeg_flat, 256);

        let result = MuseProcessedData {
            eeg,
            ppg_ir: vec![],
            ppg_red: vec![],
            ppg_nir: vec![],
            spo2: None,
            fnirs_hbo2: None,
            fnirs_hbr: None,
            fnirs_tsi: None,
            accel: state.accel_buffer,
            gyro: state.gyro_buffer,
            timestamp: get_timestamp(),
            battery: 0.0,
            packet_types: vec![MusePacketType::Eeg],
            signal_quality,
            mindfulness,
            restfulness,
            alpha: band_powers.as_ref().map(|b| b.alpha),
            beta: band_powers.as_ref().map(|b| b.beta),
            gamma: band_powers.as_ref().map(|b| b.gamma),
            delta: band_powers.as_ref().map(|b| b.delta),
            theta: band_powers.as_ref().map(|b| b.theta),
        };

        for buf in &mut state.eeg_buffers {
            buf.clear();
        }
        for received in &mut state.received_eeg_channels {
            *received = false;
        }

        Some(result)
    } else {
        None
    }
}

fn parse_eeg_samples(data: &[u8], resolution: EegResolution) -> Vec<f64> {
    let scale = resolution.scale_factor();
    let offset = resolution.offset();

    let mut samples = Vec::with_capacity(12);
    for i in (0..data.len()).step_by(3) {
        if i + 2 < data.len() {
            let val1 = ((data[i] as u16) << 4) | ((data[i + 1] >> 4) as u16);
            let val2 = (((data[i + 1] & 0x0F) as u16) << 8) | (data[i + 2] as u16);

            let scaled1 = ((val1 as f64) - offset) * scale;
            let scaled2 = ((val2 as f64) - offset) * scale;
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
        ppg_nir: vec![],
        spo2: None,
        fnirs_hbo2: None,
        fnirs_hbr: None,
        fnirs_tsi: None,
        accel: state.accel_buffer,
        gyro: [0.0; 3],
        timestamp: get_timestamp(),
        battery: 0.0,
        packet_types: vec![MusePacketType::Accel],
        signal_quality: 100.0,
        mindfulness: None,
        restfulness: None,
        alpha: None,
        beta: None,
        gamma: None,
        delta: None,
        theta: None,
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
        ppg_nir: vec![],
        spo2: None,
        fnirs_hbo2: None,
        fnirs_hbr: None,
        fnirs_tsi: None,
        accel: [0.0; 3],
        gyro: state.gyro_buffer,
        timestamp: get_timestamp(),
        battery: 0.0,
        packet_types: vec![MusePacketType::Gyro],
        signal_quality: 100.0,
        mindfulness: None,
        restfulness: None,
        alpha: None,
        beta: None,
        gamma: None,
        delta: None,
        theta: None,
    })
}

fn parse_ppg_data(state: &mut MuseState, ppg_idx: usize, data: &[u8]) -> Option<MuseProcessedData> {
    let ppg_count = state.ppg_channel_count();
    if ppg_idx >= ppg_count || !state.model.has_ppg() {
        return None;
    }

    let ppg_values = parse_ppg_samples(&data[2..]);
    state.ppg_buffer[ppg_idx] = ppg_values;

    let has_ppg = state
        .ppg_buffer
        .iter()
        .take(ppg_count)
        .filter(|v| !v.is_empty())
        .count()
        >= 2;

    if has_ppg {
        let ppg_ir = state.ppg_buffer[0].clone();
        let ppg_red = if ppg_count >= 2 {
            state.ppg_buffer[1].clone()
        } else {
            vec![]
        };
        let ppg_nir = if ppg_count >= 3 {
            state.ppg_buffer[2].clone()
        } else {
            vec![]
        };

        let spo2 = calculate_spo2(&ppg_ir, &ppg_red);

        let (fnirs_hbo2, fnirs_hbr, fnirs_tsi) = if state.model.has_fnirs() && ppg_count >= 3 {
            calculate_fnirs(&ppg_ir, &ppg_nir, &ppg_red)
        } else {
            (None, None, None)
        };

        for buf in &mut state.ppg_buffer {
            buf.clear();
        }

        Some(MuseProcessedData {
            eeg: vec![],
            ppg_ir,
            ppg_red,
            ppg_nir,
            spo2,
            fnirs_hbo2,
            fnirs_hbr,
            fnirs_tsi,
            accel: [0.0; 3],
            gyro: [0.0; 3],
            timestamp: get_timestamp(),
            battery: 0.0,
            packet_types: if state.model.has_fnirs() {
                vec![MusePacketType::Fnirs]
            } else {
                vec![MusePacketType::Ppg]
            },
            signal_quality: 100.0,
            mindfulness: None,
            restfulness: None,
            alpha: None,
            beta: None,
            gamma: None,
            delta: None,
            theta: None,
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

fn calculate_fnirs(
    ppg_ir: &[f64],
    ppg_nir: &[f64],
    ppg_red: &[f64],
) -> (Option<f64>, Option<f64>, Option<f64>) {
    if ppg_ir.len() < 64 || ppg_nir.len() < 64 || ppg_red.len() < 64 {
        return (None, None, None);
    }

    let ir_mean: f64 = ppg_ir.iter().sum::<f64>() / ppg_ir.len() as f64;
    let nir_mean: f64 = ppg_nir.iter().sum::<f64>() / ppg_nir.len() as f64;
    let red_mean: f64 = ppg_red.iter().sum::<f64>() / ppg_red.len() as f64;

    if ir_mean <= 0.0 || nir_mean <= 0.0 || red_mean <= 0.0 {
        return (None, None, None);
    }

    let od_ir = (ir_mean / 50000.0).ln();
    let od_nir = (nir_mean / 50000.0).ln();
    let _od_red = (red_mean / 50000.0).ln();

    let hbo2 = (od_ir * 1.05 - od_nir * 0.78) * 500.0;
    let hbr = (od_nir * 1.10 - od_ir * 0.69) * 500.0;
    let total = hbo2 + hbr;
    let tsi = if total > 0.0 {
        (hbo2 / total) * 100.0
    } else {
        0.0
    };

    (
        Some(hbo2.clamp(-100.0, 100.0)),
        Some(hbr.clamp(-100.0, 100.0)),
        Some(tsi.clamp(0.0, 100.0)),
    )
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
    if name_lower.contains("athena") {
        MuseModel::MuseSAthena
    } else if name_lower.contains("muse s") || name_lower.contains("muse-s") {
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

    let channel_count = {
        let state = MUSE_STATE.lock().unwrap();
        state.as_ref().map(|s| s.channel_count()).unwrap_or(5)
    };

    for (i, packet) in raw_packets.into_iter().enumerate() {
        let mut parsed = parse_muse_packet(i as i32, packet);
        results.append(&mut parsed);
    }
    if results.is_empty() {
        results.push(MuseProcessedData {
            eeg: vec![vec![0.0; 12]; channel_count],
            ppg_ir: vec![],
            ppg_red: vec![],
            ppg_nir: vec![],
            spo2: None,
            fnirs_hbo2: None,
            fnirs_hbr: None,
            fnirs_tsi: None,
            accel: [0.0; 3],
            gyro: [0.0; 3],
            timestamp: get_timestamp(),
            battery: 0.0,
            packet_types: vec![MusePacketType::Eeg],
            signal_quality: 100.0,
            mindfulness: None,
            restfulness: None,
            alpha: None,
            beta: None,
            gamma: None,
            delta: None,
            theta: None,
        });
    }
    results
}
