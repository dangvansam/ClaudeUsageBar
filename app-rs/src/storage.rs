use anyhow::{Context, Result};
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

const QUALIFIER: &str = "com";
const ORG: &str = "ClaudeUsageBar";
const APP: &str = "ClaudeUsageBar";
const KEYRING_SERVICE: &str = "com.claude.usagebar";
const KEYRING_USER: &str = "session-cookie";

#[derive(Copy, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ThemeMode {
    Light,
    Dark,
    System,
}

impl Default for ThemeMode {
    fn default() -> Self {
        Self::System
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Accent {
    Warm,
    Cool,
    Coral,
    Mono,
}

impl Default for Accent {
    fn default() -> Self {
        Self::Warm
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TrayIconStyle {
    Number,
    Ring,
    Mark,
}

impl Default for TrayIconStyle {
    fn default() -> Self {
        Self::Mark
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default = "default_true")]
    pub usage_notifications_enabled: bool,
    #[serde(default = "default_true")]
    pub status_notifications_enabled: bool,
    #[serde(default = "default_true")]
    pub hotkey_enabled: bool,
    #[serde(default)]
    pub show_percent_in_tray: bool,
    // Compact "(3h10m)" countdown next to the tray icon. Mirrors Swift
    // showTimeInTray; off by default to keep the tray label terse.
    #[serde(default)]
    pub show_time_in_tray: bool,
    // Render the Anthropic status line in the popover. Mirrors Swift
    // showServiceStatus; off by default so the popup stays meter-focused.
    #[serde(default)]
    pub show_service_status: bool,
    // Toggle the background update poll. On by default.
    #[serde(default = "default_true")]
    pub auto_check_for_updates: bool,
    // Worker poll interval for usage + status. Stored seconds (60 | 300 | 900).
    #[serde(default = "default_refresh_interval")]
    pub refresh_interval_seconds: u32,
    #[serde(default)]
    pub launch_at_login: bool,
    #[serde(default)]
    pub theme: ThemeMode,
    #[serde(default)]
    pub accent: Accent,
    #[serde(default)]
    pub tray_icon_style: TrayIconStyle,
    #[serde(default = "default_warn_threshold")]
    pub session_warn_threshold: u8,
    #[serde(default = "default_warn_threshold")]
    pub weekly_warn_threshold: u8,
    #[serde(default = "default_notif_template")]
    pub notif_message_template: String,
    #[serde(default)]
    pub last_notified_threshold: u8,
    #[serde(default)]
    pub last_seen_version: Option<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            usage_notifications_enabled: true,
            status_notifications_enabled: true,
            hotkey_enabled: true,
            show_percent_in_tray: false,
            show_time_in_tray: false,
            show_service_status: false,
            auto_check_for_updates: true,
            refresh_interval_seconds: default_refresh_interval(),
            launch_at_login: false,
            theme: ThemeMode::default(),
            accent: Accent::default(),
            tray_icon_style: TrayIconStyle::default(),
            session_warn_threshold: default_warn_threshold(),
            weekly_warn_threshold: default_warn_threshold(),
            notif_message_template: default_notif_template(),
            last_notified_threshold: 0,
            last_seen_version: None,
        }
    }
}

fn default_true() -> bool {
    true
}

fn default_warn_threshold() -> u8 {
    80
}

fn default_refresh_interval() -> u32 {
    300
}

fn default_notif_template() -> String {
    // Verbatim from project/app.js DEFAULTS.message.
    "Heads up — you've used {pct} of your {limit} limit. Resets {reset}.".to_string()
}

pub struct Storage;

impl Storage {
    pub fn config_dir() -> Result<PathBuf> {
        let dirs = ProjectDirs::from(QUALIFIER, ORG, APP)
            .context("could not resolve project directories")?;
        let path = dirs.config_dir().to_path_buf();
        fs::create_dir_all(&path).ok();
        Ok(path)
    }

    pub fn settings_path() -> Result<PathBuf> {
        Ok(Self::config_dir()?.join("settings.json"))
    }

    pub fn load_settings() -> Settings {
        let path = match Self::settings_path() {
            Ok(p) => p,
            Err(_) => return Settings::default(),
        };
        match fs::read_to_string(&path) {
            Ok(raw) => serde_json::from_str(&raw).unwrap_or_default(),
            Err(_) => Settings::default(),
        }
    }

    pub fn save_settings(settings: &Settings) -> Result<()> {
        let path = Self::settings_path()?;
        let raw = serde_json::to_string_pretty(settings)?;
        fs::write(&path, raw).with_context(|| format!("writing {}", path.display()))?;
        Ok(())
    }

    pub fn load_cookie() -> Option<String> {
        match keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER) {
            Ok(entry) => entry.get_password().ok().filter(|s| !s.is_empty()),
            Err(_) => Self::load_cookie_fallback(),
        }
    }

    pub fn save_cookie(cookie: &str) -> Result<()> {
        if let Ok(entry) = keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER) {
            if entry.set_password(cookie).is_ok() {
                let _ = fs::remove_file(Self::cookie_fallback_path().ok().unwrap_or_default());
                return Ok(());
            }
        }
        Self::save_cookie_fallback(cookie)
    }

    pub fn clear_cookie() -> Result<()> {
        if let Ok(entry) = keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER) {
            let _ = entry.delete_credential();
        }
        if let Ok(path) = Self::cookie_fallback_path() {
            let _ = fs::remove_file(path);
        }
        Ok(())
    }

    fn cookie_fallback_path() -> Result<PathBuf> {
        Ok(Self::config_dir()?.join("cookie.txt"))
    }

    fn load_cookie_fallback() -> Option<String> {
        let path = Self::cookie_fallback_path().ok()?;
        fs::read_to_string(path).ok().map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
    }

    fn save_cookie_fallback(cookie: &str) -> Result<()> {
        let path = Self::cookie_fallback_path()?;
        fs::write(&path, cookie)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
        }
        Ok(())
    }
}
