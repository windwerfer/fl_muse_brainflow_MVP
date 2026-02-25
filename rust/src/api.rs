use anyhow::{Context, Result};
use brainflow::board_shim::{get_eeg_channels, BoardShim};
use brainflow::brainflow_input_params::BrainFlowInputParamsBuilder;
use brainflow::data_filter::{self, Band};
use brainflow::brainflow_model_params::BrainFlowModelParamsBuilder;
use brainflow::{BoardIds, BrainFlowClassifiers, BrainFlowMetrics, BrainFlowPresets, WindowOperations};
use flutter_rust_bridge::frb;
use log::info;
use std::sync::Mutex;

// Static Mutex to hold the BoardShim instance (shared across calls)
static BOARD: Mutex<Option<BoardShim>> = Mutex::new(None);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionStatus {
    Disconnected,
    Connecting,
    Connected,
    Error,
}

#[frb]
pub async fn connect_to_muse(mac_address: Option<String>) -> Result<String> {
    info!("Connecting to Muse... mac: {:?}", mac_address);
    info!("Target OS: {}", std::env::consts::OS);

    let mut board_guard = BOARD
        .lock()
        .map_err(|_| anyhow::anyhow!("Failed to lock BOARD mutex"))?;

    if board_guard.is_some() {
        info!("Already connected/initialized.");
        return Ok("Already connected".to_string());
    }

    let mut builder = BrainFlowInputParamsBuilder::new();
    if let Some(mac) = mac_address {
        if !mac.is_empty() {
            builder = builder.mac_address(mac);
        }
    }
    let params = builder.build();

    // let board_id = BoardIds::MuseSBoard;
    let board_id = BoardIds::SyntheticBoard;

    let board = BoardShim::new(board_id, params)
        .map_err(|e| anyhow::anyhow!("Failed to create BoardShim: {:?}", e))?;

    board
        .prepare_session()
        .map_err(|e| anyhow::anyhow!("Failed to prepare session: {:?}", e))?;

    board
        .start_stream(45000, "")
        .map_err(|e| anyhow::anyhow!("Failed to start stream: {:?}", e))?;

    *board_guard = Some(board);
    info!("Muse connected and streaming started.");

    Ok("Connected successfully".to_string())
}

pub async fn disconnect_muse() -> Result<String> {
    let mut board_guard = BOARD
        .lock()
        .map_err(|_| anyhow::anyhow!("Failed to lock BOARD mutex"))?;

    if let Some(board) = board_guard.take() {
        if board.is_prepared().unwrap_or(false) {
            board.stop_stream().ok();
            board.release_session().ok();
        }
    }

    info!("Muse disconnected.");
    Ok("Disconnected".to_string())
}

pub fn get_connection_status() -> ConnectionStatus {
    let board_guard = match BOARD.lock() {
        Ok(g) => g,
        Err(_) => return ConnectionStatus::Error,
    };

    if let Some(board) = &*board_guard {
        match board.is_prepared() {
            Ok(true) => ConnectionStatus::Connected,
            Ok(false) => ConnectionStatus::Disconnected,
            Err(_) => ConnectionStatus::Error,
        }
    } else {
        ConnectionStatus::Disconnected
    }
}

pub struct EegData {
    pub channels: Vec<usize>,
    pub data: Vec<Vec<f64>>, // [channel][sample]
}

pub async fn get_latest_data(num_samples: i32) -> Result<EegData> {
    let board_guard = BOARD
        .lock()
        .map_err(|_| anyhow::anyhow!("Failed to lock BOARD mutex"))?;

    let board = board_guard.as_ref().context("Board not initialized")?;

    let eeg_channels = get_eeg_channels(BoardIds::MuseSBoard, BrainFlowPresets::DefaultPreset)
        .map_err(|e| anyhow::anyhow!("Failed to get EEG channels: {:?}", e))?;

    let data = board
        .get_current_board_data(num_samples as usize, BrainFlowPresets::DefaultPreset)
        .map_err(|e| anyhow::anyhow!("Failed to get board data: {:?}", e))?;

    let mut result_data = Vec::new();
    for &channel_idx in &eeg_channels {
        if (channel_idx as usize) < data.nrows() {
            let channel_data = data.row(channel_idx as usize).to_vec();
            result_data.push(channel_data);
        }
    }

    Ok(EegData {
        channels: eeg_channels,
        data: result_data,
    })
}

pub fn verify_brainflow_version() -> Result<String> {
    brainflow::board_shim::get_version().map_err(|e| anyhow::anyhow!("BrainFlow error: {:?}", e))
}

pub fn test_output() -> String {
    info!(
        "Test logging from Rust - Target OS: {}",
        std::env::consts::OS
    );
    "Test output from Rust".to_string()
}

// Initialize logger
pub fn init_logger() {
    let _ = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .try_init();
}

#[frb]
pub fn calculate_signal_quality(data: Vec<f64>, sampling_rate: usize) -> f64 {
    let data_len = data.len();
    if data_len < 32 {
        return 100.0;
    }

    let mut data = data;
    let gain = 1;
    
    match data_filter::get_railed_percentage(&mut data, data_len, gain) {
        Ok(railed) => {
            let quality = (100.0 - railed * 100.0).max(0.0).min(100.0);
            quality
        }
        Err(_) => {
            let std = calculate_std(&data);
            if std < 1.0 {
                0.0
            } else if std < 10.0 {
                50.0
            } else {
                100.0
            }
        }
    }
}

fn calculate_std(data: &[f64]) -> f64 {
    if data.is_empty() {
        return 0.0;
    }
    let mean: f64 = data.iter().sum::<f64>() / data.len() as f64;
    let variance: f64 = data.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / data.len() as f64;
    variance.sqrt()
}

#[frb]
pub fn predict_mindfulness(eeg_data: Vec<f64>, sampling_rate: usize) -> Option<f64> {
    if eeg_data.len() < 256 {
        return None;
    }

    let params = BrainFlowModelParamsBuilder::new()
        .metric(BrainFlowMetrics::Mindfulness)
        .classifier(BrainFlowClassifiers::DefaultClassifier)
        .build();

    match brainflow::ml_model::MlModel::new(params) {
        Ok(mut model) => {
            if model.prepare().is_ok() {
                let mut data = eeg_data;
                if let Ok(result) = model.predict(&mut data) {
                    if let Some(&score) = result.first() {
                        return Some(score.clamp(0.0, 100.0));
                    }
                }
            }
        }
        Err(_) => {}
    }
    None
}

#[frb]
pub fn predict_restfulness(eeg_data: Vec<f64>, sampling_rate: usize) -> Option<f64> {
    if eeg_data.len() < 256 {
        return None;
    }

    let params = BrainFlowModelParamsBuilder::new()
        .metric(BrainFlowMetrics::Restfulness)
        .classifier(BrainFlowClassifiers::DefaultClassifier)
        .build();

    match brainflow::ml_model::MlModel::new(params) {
        Ok(mut model) => {
            if model.prepare().is_ok() {
                let mut data = eeg_data;
                if let Ok(result) = model.predict(&mut data) {
                    if let Some(&score) = result.first() {
                        return Some(score.clamp(0.0, 100.0));
                    }
                }
            }
        }
        Err(_) => {}
    }
    None
}

#[frb]
pub struct BandPowers {
    pub delta: f64,
    pub theta: f64,
    pub alpha: f64,
    pub beta: f64,
    pub gamma: f64,
}

#[frb]
pub fn calculate_band_powers(eeg_data: Vec<f64>, sampling_rate: usize) -> Option<BandPowers> {
    if eeg_data.len() < 256 {
        return None;
    }

    let mut data = eeg_data;
    
    let window = WindowOperations::Hamming;
    
    match data_filter::get_psd(&mut data, sampling_rate, window) {
        Ok(psd) => {
            let bands = vec![
                Band { freq_start: 1.0, freq_stop: 4.0 },
                Band { freq_start: 4.0, freq_stop: 8.0 },
                Band { freq_start: 8.0, freq_stop: 13.0 },
                Band { freq_start: 13.0, freq_stop: 30.0 },
                Band { freq_start: 30.0, freq_stop: 45.0 },
            ];
            
            let mut powers = Vec::new();
            let mut psd = psd;
            for band in bands {
                if let Ok(power) = data_filter::get_band_power(&mut psd, band) {
                    powers.push(power);
                } else {
                    powers.push(0.0);
                }
            }
            
            Some(BandPowers {
                delta: powers.get(0).copied().unwrap_or(0.0),
                theta: powers.get(1).copied().unwrap_or(0.0),
                alpha: powers.get(2).copied().unwrap_or(0.0),
                beta: powers.get(3).copied().unwrap_or(0.0),
                gamma: powers.get(4).copied().unwrap_or(0.0),
            })
        }
        Err(_) => None,
    }
}
