use parking_lot::Mutex;
use std::sync::Arc;

use crate::api::{StatusSummary, UpdateInfo, UsageSnapshot};
use crate::storage::Settings;

#[derive(Default)]
pub struct AppState {
    pub cookie: String,
    pub usage: Option<UsageSnapshot>,
    pub status: Option<StatusSummary>,
    pub update: Option<UpdateInfo>,
    pub settings: Settings,
    pub last_error: Option<String>,
    pub loading: bool,
}

pub type SharedState = Arc<Mutex<AppState>>;

#[derive(Clone, Debug)]
pub enum UiCommand {
    RefreshNow,
    SaveCookie(String),
    ClearCookie,
    UpdateSettings(Settings),
    CheckUpdates,
    HideWindow,
}
