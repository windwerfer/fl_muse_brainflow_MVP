use anyhow::{Context, Result};
use brainflow::board_shim::{get_eeg_channels, BoardShim};
use brainflow::brainflow_input_params::BrainFlowInputParamsBuilder;
use brainflow::{BoardIds, BrainFlowPresets};
use log::info;
use std::sync::Mutex;

// Use a static Mutex to hold the BoardShim instance
static BOARD: Mutex<Option<BoardShim>> = Mutex::new(None);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionStatus {
    Disconnected,
    Connecting,
    Connected,
    Error,
}

pub fn connect_to_muse(mac_address: Option<String>) -> Result<()> {
    info!("Connecting to Muse...");
    let mut board_guard = BOARD
        .lock()
        .map_err(|_| anyhow::anyhow!("Failed to lock BOARD mutex"))?;

    if board_guard.is_some() {
        return Ok(()); // Already connected or initialized
    }

    let mut builder = BrainFlowInputParamsBuilder::new();
    if let Some(mac) = mac_address {
        if !mac.is_empty() {
            builder = builder.mac_address(mac);
        }
    }

    let params = builder.build();
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
    Ok(())
}

pub fn disconnect_muse() -> Result<()> {
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
    Ok(())
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

pub fn get_latest_data(num_samples: i32) -> Result<EegData> {
    let board_guard = BOARD
        .lock()
        .map_err(|_| anyhow::anyhow!("Failed to lock BOARD mutex"))?;
    let board = board_guard.as_ref().context("Board not initialized")?;

    let eeg_channels = get_eeg_channels(BoardIds::SyntheticBoard, BrainFlowPresets::DefaultPreset)
        .map_err(|e| anyhow::anyhow!("Failed to get EEG channels: {:?}", e))?;

    let data = board
        .get_current_board_data(num_samples as usize, BrainFlowPresets::DefaultPreset)
        .map_err(|e| anyhow::anyhow!("Failed to get board data: {:?}", e))?;

    // data is Array2<f64> [channels, samples]
    let mut result_data = Vec::new();
    for &channel_idx in &eeg_channels {
        if channel_idx < data.nrows() {
            let channel_data = data.row(channel_idx).to_vec();
            result_data.push(channel_data);
        }
    }

    Ok(EegData {
        channels: eeg_channels,
        data: result_data,
    })
}

// Initialize logger
pub fn init_logger() {
    let _ = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .try_init();
}
