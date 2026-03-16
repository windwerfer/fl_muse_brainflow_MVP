use crate::api;
use crate::muse_types::{
    EegResolution, MuseModel, MusePacketType, MuseProcessedData, MUSE_ACCEL_SCALE_FACTOR,
    MUSE_GYRO_SCALE_FACTOR,
};
use flutter_rust_bridge::frb;
use log::info;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

static MUSE_STATE: Mutex<Option<MuseState>> = Mutex::new(None);

const MAX_PPG_CHANNELS: usize = 3;

struct MuseState {
    model: MuseModel,
    eeg_buffers: Vec<Vec<f64>>,
    eeg_accumulator: Vec<Vec<f64>>, // Rolling buffer for band powers (256+ samples)
    accel_buffer: [f64; 3],
    gyro_buffer: [f64; 3],
    ppg_buffer: Vec<Vec<f64>>,
    package_count: u16,
    initialized: bool,
    battery: f64,
}

impl MuseState {
    fn new(model: MuseModel) -> Self {
        let channel_count = model.channel_count();
        Self {
            model,
            eeg_buffers: vec![Vec::new(); channel_count],
            eeg_accumulator: vec![Vec::new(); channel_count], // Initialize accumulator
            accel_buffer: [0.0; 3],
            gyro_buffer: [0.0; 3],
            ppg_buffer: vec![Vec::new(); MAX_PPG_CHANNELS],
            package_count: 0,
            initialized: true,
            battery: -1.0,
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
    // uncomment to see when packages arrive from muse_ble_service.dart
    // info!(
    //     "[RUST] parse_muse_packet called, channel={}, data_len={}",
    //     channel,
    //     data.len()
    // );
    let mut results = Vec::new();

    {
        let mut state = MUSE_STATE.lock().unwrap();
        if state.is_none() {
            *state = Some(MuseState::new(MuseModel::MuseS));
        }
    }

    let mut state = MUSE_STATE.lock().unwrap();
    let muse_state = state.as_mut().unwrap();

    // println!("[RUST] eeg[0] called, channel={}", channel);

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
        10 => {
            if let Some(data) = parse_battery_data(muse_state, &data) {
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
        info!(
            "[RUST] Channel {} >= channel_count {}, skipping",
            channel, channel_count
        );
        return None;
    }

    let package_num = ((data[0] as u16) << 8) | (data[1] as u16);
    state.package_count = package_num;

    let resolution = state.model.resolution();
    let new_samples = parse_eeg_samples(&data[2..], resolution);

    info!(
        "[RUST] Channel {}: got {} new samples, accumulator len before: {}",
        channel,
        new_samples.len(),
        state.eeg_accumulator[channel].len()
    );

    // Update buffer with the latest batch for this channel (for immediate EEG display)
    state.eeg_buffers[channel] = new_samples.clone();

    // ACCUMULATE samples for band power calculation (rolling window)
    state.eeg_accumulator[channel].extend_from_slice(&new_samples);
    // Keep rolling window of 256 samples per channel (1 second at 256Hz)
    const MAX_ACCUMULATOR: usize = 256;
    if state.eeg_accumulator[channel].len() > MAX_ACCUMULATOR {
        let excess = state.eeg_accumulator[channel].len() - MAX_ACCUMULATOR;
        state.eeg_accumulator[channel].drain(0..excess);
    }

    info!(
        "[RUST] Channel {}: accumulator len after: {}",
        channel,
        state.eeg_accumulator[channel].len()
    );

    // Check if ANY channel has enough samples for band power calculation
    // (not ALL channels - some like LeftAUX may not be streaming by default)
    let max_accumulator = state
        .eeg_accumulator
        .iter()
        .map(|v| v.len())
        .max()
        .unwrap_or(0);

    let channels_with_data: Vec<usize> = state
        .eeg_accumulator
        .iter()
        .enumerate()
        .filter(|(_, v)| !v.is_empty())
        .map(|(i, _)| i)
        .collect();

    info!(
        "[RUST] Max accumulator: {}, channels with data: {:?}",
        max_accumulator, channels_with_data
    );

    // Build FULL rectangular eeg vector: latest known samples for EVERY channel
    let mut full_eeg: Vec<Vec<f64>> = Vec::with_capacity(channel_count);
    for i in 0..channel_count {
        if state.eeg_buffers[i].is_empty() {
            full_eeg.push(vec![0.0; new_samples.len()]);
        } else {
            full_eeg.push(state.eeg_buffers[i].clone());
        }
    }

    // Calculate band powers only when we have enough accumulated samples
    let (sq, mind, rest, concentration, relaxation, band_powers) = if max_accumulator >= 256 {
        info!(
            "[RUST] Buffer full ({} samples), calling BrainFlow calculate_band_powers",
            max_accumulator
        );

        let all_eeg_flat: Vec<f64> = state.eeg_accumulator.iter().flatten().copied().collect();
        info!("[RUST] Flattened EEG size: {}", all_eeg_flat.len());

        let sq = api::calculate_signal_quality(all_eeg_flat.clone(), 256);
        let bp = api::calculate_band_powers(all_eeg_flat.clone(), 256);

        info!(
            "[RUST] Band powers result: alpha={:?}, beta={:?}, delta={:?}, theta={:?}",
            bp.as_ref().map(|b| b.alpha),
            bp.as_ref().map(|b| b.beta),
            bp.as_ref().map(|b| b.delta),
            bp.as_ref().map(|b| b.theta)
        );

        // Use band powers for ML predictions (may fail if ML model files missing)
        let mind = bp
            .as_ref()
            .map(|bands| api::predict_mindfulness_from_band_powers(bands.clone()))
            .flatten();
        let rest = bp
            .as_ref()
            .map(|bands| api::predict_restfulness_from_band_powers(bands.clone()))
            .flatten();

        // Also calculate band-power-ratio based metrics (always available)
        let concentration = bp
            .as_ref()
            .map(|bands| api::calculate_concentration(bands.clone()));
        let relaxation = bp
            .as_ref()
            .map(|bands| api::calculate_relaxation(bands.clone()));

        info!(
            "[RUST] Concentration: {:?}, Relaxation: {:?}",
            concentration, relaxation
        );

        (sq, mind, rest, concentration, relaxation, bp)
    } else {
        // Not enough samples yet - use last known values or defaults
        let all_eeg_flat: Vec<f64> = full_eeg.iter().flatten().copied().collect();
        let sq = api::calculate_signal_quality(all_eeg_flat.clone(), 256);
        (sq, None, None, None, None, None)
    };

    // Timestamp with simple drift correction (package_num / sampling rate)
    let timestamp = get_timestamp() - (package_num as f64 / 256.0);

    let result = MuseProcessedData {
        eeg: full_eeg,
        ppg_ir: vec![],
        ppg_red: vec![],
        ppg_nir: vec![],
        spo2: None,
        fnirs_hbo2: None,
        fnirs_hbr: None,
        fnirs_tsi: None,
        accel: state.accel_buffer,
        gyro: state.gyro_buffer,
        timestamp,
        battery: 0.0,
        packet_types: vec![MusePacketType::Eeg],
        signal_quality: sq,
        mindfulness: mind,
        restfulness: rest,
        concentration,
        relaxation,
        alpha: band_powers.as_ref().map(|b| b.alpha),
        beta: band_powers.as_ref().map(|b| b.beta),
        gamma: band_powers.as_ref().map(|b| b.gamma),
        delta: band_powers.as_ref().map(|b| b.delta),
        theta: band_powers.as_ref().map(|b| b.theta),
    };

    Some(result)
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
        concentration: None,
        relaxation: None,
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
        concentration: None,
        relaxation: None,
        alpha: None,
        beta: None,
        gamma: None,
        delta: None,
        theta: None,
    })
}

fn parse_battery_data(state: &mut MuseState, data: &[u8]) -> Option<MuseProcessedData> {
    if data.len() < 4 {
        return None;
    }

    let battery_val = ((data[2] as u16) | ((data[3] as u16) << 8)) as f64;
    let battery_percent = (battery_val / 512.0 * 100.0).clamp(0.0, 100.0);
    state.battery = battery_percent;

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
        gyro: [0.0; 3],
        timestamp: get_timestamp(),
        battery: state.battery,
        packet_types: vec![MusePacketType::Battery],
        signal_quality: 100.0,
        mindfulness: None,
        restfulness: None,
        concentration: None,
        relaxation: None,
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
            concentration: None,
            relaxation: None,
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
            concentration: None,
            relaxation: None,
            alpha: None,
            beta: None,
            gamma: None,
            delta: None,
            theta: None,
        });
    }

    results
}
