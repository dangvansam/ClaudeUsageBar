#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod api;
mod autostart;
mod hotkey;
mod icon;
mod notify;
mod platform;
mod popup;
mod state;
mod storage;
mod tray;

use anyhow::Result;
use eframe::egui::{IconData, ViewportBuilder};
use global_hotkey::GlobalHotKeyEvent;
use parking_lot::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tray_icon::menu::MenuEvent;
use tray_icon::TrayIconEvent;

use crate::api::{ClaudeClient, StatusClient, UpdateClient};
use crate::hotkey::HotkeyController;
use crate::icon::render_app_icon;
use crate::notify::Notifier;
use crate::popup::PopupApp;
use crate::state::{AppState, SharedState, UiCommand};
use crate::storage::Storage;
use crate::tray::TrayController;

const CURRENT_VERSION: &str = env!("CARGO_PKG_VERSION");
// Status fetch is cheaper than usage and rarely changes; keep it fixed at 10 min.
const STATUS_INTERVAL_SECS: u64 = 600;
// Update poll cadence when auto-check is on. Gated by `auto_check_for_updates`.
const UPDATE_INTERVAL_SECS: u64 = 3600;

fn main() -> Result<()> {
    init_logging();
    log::info!("ClaudeUsageBar v{} starting", CURRENT_VERSION);

    platform::after_startup_checks();

    let settings = Storage::load_settings();
    let cookie = Storage::load_cookie().unwrap_or_default();

    let state: SharedState = Arc::new(Mutex::new(AppState {
        cookie: cookie.clone(),
        settings: settings.clone(),
        ..AppState::default()
    }));

    let (cmd_tx, cmd_rx) = channel::<UiCommand>();
    let visible = Arc::new(AtomicBool::new(false));
    let want_quit = Arc::new(AtomicBool::new(false));

    spawn_worker(state.clone(), cmd_rx, want_quit.clone());

    if let Err(e) = autostart::set_launch_at_login(settings.launch_at_login) {
        log::warn!("autostart sync failed: {}", e);
    }

    run_ui(state, cmd_tx, visible, want_quit)
}

fn init_logging() {
    let mut builder = env_logger::Builder::from_default_env();
    builder.filter_level(log::LevelFilter::Info);
    let _ = builder.try_init();
}

fn spawn_worker(state: SharedState, cmd_rx: Receiver<UiCommand>, want_quit: Arc<AtomicBool>) {
    std::thread::Builder::new()
        .name("usage-worker".into())
        .spawn(move || worker_loop(state, cmd_rx, want_quit))
        .expect("spawn worker thread");
}

fn worker_loop(state: SharedState, cmd_rx: Receiver<UiCommand>, want_quit: Arc<AtomicBool>) {
    let claude = ClaudeClient::new();
    let status_client = StatusClient::new();
    let update_client = UpdateClient::new();

    let mut last_refresh = Instant::now().checked_sub(Duration::from_secs(3600)).unwrap_or_else(Instant::now);
    let mut last_status = last_refresh;
    let mut last_update = last_refresh;

    loop {
        if want_quit.load(Ordering::SeqCst) {
            return;
        }

        if let Ok(cmd) = cmd_rx.recv_timeout(Duration::from_millis(500)) {
            handle_command(&state, &claude, &update_client, cmd, &mut last_refresh);
        }

        // Read current poll cadence + auto-update flag from settings each tick so
        // that flipping the toggles in the popup takes effect within 500 ms.
        let (refresh_interval, auto_check) = {
            let st = state.lock();
            (
                Duration::from_secs(st.settings.refresh_interval_seconds.max(60) as u64),
                st.settings.auto_check_for_updates,
            )
        };

        let now = Instant::now();
        if now.duration_since(last_refresh) >= refresh_interval {
            refresh_usage(&state, &claude);
            last_refresh = now;
        }
        if now.duration_since(last_status) >= Duration::from_secs(STATUS_INTERVAL_SECS) {
            refresh_status(&state, &status_client);
            last_status = now;
        }
        if auto_check && now.duration_since(last_update) >= Duration::from_secs(UPDATE_INTERVAL_SECS) {
            refresh_update(&state, &update_client);
            last_update = now;
        }
    }
}

fn handle_command(
    state: &SharedState,
    claude: &ClaudeClient,
    update_client: &UpdateClient,
    cmd: UiCommand,
    last_refresh: &mut Instant,
) {
    match cmd {
        UiCommand::RefreshNow => {
            refresh_usage(state, claude);
            *last_refresh = Instant::now();
        }
        UiCommand::SaveCookie(c) => {
            if let Err(e) = Storage::save_cookie(&c) {
                log::error!("save cookie: {}", e);
                state.lock().last_error = Some(format!("Could not save cookie: {}", e));
            } else {
                state.lock().cookie = c;
                refresh_usage(state, claude);
                *last_refresh = Instant::now();
            }
        }
        UiCommand::ClearCookie => {
            let _ = Storage::clear_cookie();
            let mut st = state.lock();
            st.cookie.clear();
            st.usage = None;
            st.last_error = None;
            st.settings.last_notified_threshold = 0;
            let _ = Storage::save_settings(&st.settings);
        }
        UiCommand::UpdateSettings(new_settings) => {
            let prev = {
                let mut st = state.lock();
                let prev = st.settings.clone();
                st.settings = new_settings.clone();
                prev
            };
            if let Err(e) = Storage::save_settings(&new_settings) {
                log::error!("save settings: {}", e);
            }
            if new_settings.launch_at_login != prev.launch_at_login {
                if let Err(e) = autostart::set_launch_at_login(new_settings.launch_at_login) {
                    log::warn!("autostart toggle: {}", e);
                }
            }
        }
        UiCommand::CheckUpdates => refresh_update(state, update_client),
        UiCommand::HideWindow => {}
    }
}

fn refresh_usage(state: &SharedState, claude: &ClaudeClient) {
    let cookie = {
        let mut st = state.lock();
        st.loading = true;
        st.cookie.clone()
    };
    if cookie.trim().is_empty() {
        let mut st = state.lock();
        st.loading = false;
        st.last_error = Some("Session cookie not set".into());
        return;
    }
    match claude.fetch_usage(&cookie) {
        Ok(snapshot) => {
            let percent = snapshot.session_percent();
            let mut st = state.lock();
            st.usage = Some(snapshot);
            st.last_error = None;
            st.loading = false;
            if st.settings.usage_notifications_enabled {
                let reset = st
                    .usage
                    .as_ref()
                    .and_then(|u| u.session.resets_at)
                    .map(format_reset_label);
                let template = st.settings.notif_message_template.clone();
                if let Some(new_threshold) = Notifier::maybe_notify_threshold(
                    percent,
                    st.settings.last_notified_threshold,
                    &template,
                    reset.as_deref(),
                ) {
                    st.settings.last_notified_threshold = new_threshold;
                    let _ = Storage::save_settings(&st.settings);
                } else {
                    let reset =
                        Notifier::reset_threshold_if_dropped(percent, st.settings.last_notified_threshold);
                    if reset != st.settings.last_notified_threshold {
                        st.settings.last_notified_threshold = reset;
                        let _ = Storage::save_settings(&st.settings);
                    }
                }
            }
        }
        Err(e) => {
            let mut st = state.lock();
            st.loading = false;
            st.last_error = Some(format!("{}", e));
            log::warn!("fetch usage failed: {}", e);
        }
    }
}

fn refresh_status(state: &SharedState, status: &StatusClient) {
    match status.fetch() {
        Ok(summary) => {
            let notify = {
                let mut st = state.lock();
                let was_healthy = st.status.as_ref().map(|s| s.indicator.is_healthy()).unwrap_or(true);
                let is_healthy = summary.indicator.is_healthy();
                let should_notify =
                    st.settings.status_notifications_enabled && was_healthy && !is_healthy;
                st.status = Some(summary.clone());
                should_notify
            };
            if notify {
                Notifier::send_status(summary.indicator.label(), &summary.description);
            }
        }
        Err(e) => log::debug!("status fetch failed: {}", e),
    }
}

fn refresh_update(state: &SharedState, client: &UpdateClient) {
    match client.fetch() {
        Ok(info) => {
            if info.is_newer_than(CURRENT_VERSION) {
                let notify = {
                    let mut st = state.lock();
                    let already = st.settings.last_seen_version.as_deref() == Some(info.version.as_str());
                    st.update = Some(info.clone());
                    if !already {
                        st.settings.last_seen_version = Some(info.version.clone());
                        let _ = Storage::save_settings(&st.settings);
                    }
                    !already
                };
                if notify {
                    Notifier::send_update_available(&info.version);
                }
            } else {
                state.lock().update = None;
            }
        }
        Err(e) => log::debug!("update check failed: {}", e),
    }
}

fn run_ui(
    state: SharedState,
    cmd_tx: Sender<UiCommand>,
    visible: Arc<AtomicBool>,
    want_quit: Arc<AtomicBool>,
) -> Result<()> {
    let icon = render_app_icon(256);
    let icon_data = IconData {
        rgba: icon.rgba,
        width: icon.width,
        height: icon.height,
    };

    let viewport = ViewportBuilder::default()
        .with_title("Claude Usage")
        // 440x500 mirrors the macOS popover popup (440 wide so reset strings fit
        // on one line). Settings expands the window to 920x680 dynamically.
        .with_inner_size([440.0, 500.0])
        .with_min_inner_size([400.0, 360.0])
        .with_visible(false)
        .with_decorations(true)
        .with_always_on_top()
        .with_icon(icon_data);

    let options = eframe::NativeOptions {
        viewport,
        run_and_return: true,
        ..Default::default()
    };

    let tray_state = TrayShared::new(state.clone(), cmd_tx.clone(), visible.clone());
    let want_quit_for_closure = want_quit.clone();

    let result = eframe::run_native(
        "ClaudeUsageBar",
        options,
        Box::new(move |cc| {
            let app = PopupApp::new(state.clone(), cmd_tx.clone(), visible.clone());

            #[cfg(target_os = "linux")]
            {
                init_tray_and_hotkey(
                    cc.egui_ctx.clone(),
                    tray_state.clone(),
                    want_quit_for_closure.clone(),
                );
                Ok(Box::new(app))
            }

            // On Windows/macOS the tray icon and global hotkey hold thread-affine
            // handles, so they live on this UI thread and are pumped each frame.
            #[cfg(not(target_os = "linux"))]
            {
                let _ = &cc;
                let app = match build_frame_pump(tray_state.clone(), want_quit_for_closure.clone()) {
                    Some(hook) => app.with_frame_hook(hook),
                    None => app,
                };
                Ok(Box::new(app))
            }
        }),
    );

    want_quit.store(true, Ordering::SeqCst);
    result.map_err(|e| anyhow::anyhow!("eframe: {}", e))
}

#[derive(Clone)]
struct TrayShared {
    state: SharedState,
    cmd_tx: Sender<UiCommand>,
    visible: Arc<AtomicBool>,
}

impl TrayShared {
    fn new(state: SharedState, cmd_tx: Sender<UiCommand>, visible: Arc<AtomicBool>) -> Self {
        Self { state, cmd_tx, visible }
    }
}

#[cfg(target_os = "linux")]
fn init_tray_and_hotkey(ctx: eframe::egui::Context, shared: TrayShared, want_quit: Arc<AtomicBool>) {
    std::thread::Builder::new()
        .name("tray-thread".into())
        .spawn(move || {
            if let Err(e) = gtk::init() {
                log::error!("gtk init failed: {}", e);
                return;
            }
            let tray = match TrayController::build() {
                Ok(t) => t,
                Err(e) => {
                    log::error!("tray build failed: {}", e);
                    return;
                }
            };
            let mut hotkey = HotkeyController::new().ok();
            let initial_hotkey = shared.state.lock().settings.hotkey_enabled;
            if let Some(hk) = hotkey.as_mut() {
                let _ = hk.set_enabled(initial_hotkey);
            }
            event_pump_loop(ctx, shared, tray, hotkey, want_quit);
        })
        .expect("spawn tray thread");
}

/// Build the per-frame tray + hotkey pump used on Windows/macOS, where these
/// handles are thread-affine and must live on the UI thread. Returns `None` if
/// the tray could not be created (the app still runs without a tray icon).
#[cfg(not(target_os = "linux"))]
fn build_frame_pump(
    shared: TrayShared,
    want_quit: Arc<AtomicBool>,
) -> Option<Box<dyn FnMut(&eframe::egui::Context)>> {
    let tray = match TrayController::build() {
        Ok(t) => t,
        Err(e) => {
            log::error!("tray build failed: {}", e);
            return None;
        }
    };
    let mut hotkey = HotkeyController::new().ok();
    let initial_hotkey = shared.state.lock().settings.hotkey_enabled;
    if let Some(hk) = hotkey.as_mut() {
        let _ = hk.set_enabled(initial_hotkey);
    }
    let mut pump = PumpState::new(&shared);
    Some(Box::new(move |ctx: &eframe::egui::Context| {
        pump_once(ctx, &shared, &tray, &mut hotkey, &want_quit, &mut pump);
    }))
}

/// Mutable state carried between pump iterations.
struct PumpState {
    last_settings_hotkey: bool,
    last_tray_render: Option<(
        Option<u8>,
        String,
        bool,
        crate::storage::TrayIconStyle,
        crate::storage::Accent,
    )>,
}

impl PumpState {
    fn new(shared: &TrayShared) -> Self {
        Self {
            last_settings_hotkey: shared.state.lock().settings.hotkey_enabled,
            last_tray_render: None,
        }
    }
}

#[cfg(target_os = "linux")]
fn event_pump_loop(
    ctx: eframe::egui::Context,
    shared: TrayShared,
    tray: TrayController,
    mut hotkey: Option<HotkeyController>,
    want_quit: Arc<AtomicBool>,
) {
    let mut pump = PumpState::new(&shared);
    while !want_quit.load(Ordering::SeqCst) {
        std::thread::sleep(std::time::Duration::from_millis(80));
        pump_once(&ctx, &shared, &tray, &mut hotkey, &want_quit, &mut pump);
        while gtk::events_pending() {
            gtk::main_iteration_do(false);
        }
    }
}

/// One non-blocking poll of tray menu, tray click, and hotkey event channels,
/// plus a refresh of the tray icon/tooltip when the usage state changes.
fn pump_once(
    ctx: &eframe::egui::Context,
    shared: &TrayShared,
    tray: &TrayController,
    hotkey: &mut Option<HotkeyController>,
    want_quit: &Arc<AtomicBool>,
    pump: &mut PumpState,
) {
    let menu_rx = MenuEvent::receiver();
    let tray_rx = TrayIconEvent::receiver();
    let hotkey_rx = GlobalHotKeyEvent::receiver();

    if let Ok(ev) = menu_rx.try_recv() {
        let id = ev.id.0.as_str();
        if id == tray.ids.open {
            toggle_popup(shared, ctx, true);
        } else if id == tray.ids.refresh {
            let _ = shared.cmd_tx.send(UiCommand::RefreshNow);
        } else if id == tray.ids.settings {
            toggle_popup(shared, ctx, true);
        } else if id == tray.ids.quit {
            want_quit.store(true, Ordering::SeqCst);
            ctx.send_viewport_cmd(eframe::egui::ViewportCommand::Close);
        }
    }

    if let Ok(ev) = tray_rx.try_recv() {
        if let TrayIconEvent::Click {
            button: tray_icon::MouseButton::Left,
            button_state: tray_icon::MouseButtonState::Up,
            ..
        } = ev
        {
            let was = shared.visible.load(Ordering::SeqCst);
            toggle_popup(shared, ctx, !was);
        }
    }

    if let Ok(ev) = hotkey_rx.try_recv() {
        if let Some(hk) = hotkey.as_ref() {
            if hk.matches(ev.id, ev.state) {
                let was = shared.visible.load(Ordering::SeqCst);
                toggle_popup(shared, ctx, !was);
            }
        }
    }

    let (percent, label, want_hotkey, show_percent, icon_style, accent) = {
        let st = shared.state.lock();
        let percent = st.usage.as_ref().map(|u| u.session_percent());
        let session_reset = st.usage.as_ref().and_then(|u| u.session.resets_at);
        let countdown = if st.settings.show_time_in_tray {
            session_reset.and_then(compact_time_remaining)
        } else {
            None
        };
        let label = build_tray_label(
            st.usage.as_ref().map(|u| u.session_percent()),
            st.last_error.as_deref(),
            st.settings.show_percent_in_tray,
            countdown.as_deref(),
        );
        (
            percent,
            label,
            st.settings.hotkey_enabled,
            st.settings.show_percent_in_tray,
            st.settings.tray_icon_style,
            st.settings.accent,
        )
    };

    let needs_repaint = pump
        .last_tray_render
        .as_ref()
        .map(|(p, l, sp, is, ac)| {
            *p != percent
                || l != &label
                || *sp != show_percent
                || *is != icon_style
                || *ac != accent
        })
        .unwrap_or(true);
    if needs_repaint {
        tray.update(percent, &label, show_percent, icon_style, accent);
        pump.last_tray_render = Some((percent, label, show_percent, icon_style, accent));
    }

    if want_hotkey != pump.last_settings_hotkey {
        if let Some(hk) = hotkey.as_mut() {
            let _ = hk.set_enabled(want_hotkey);
        }
        pump.last_settings_hotkey = want_hotkey;
    }
}

fn toggle_popup(shared: &TrayShared, ctx: &eframe::egui::Context, show: bool) {
    shared.visible.store(show, Ordering::SeqCst);
    ctx.request_repaint();
}

/// Compact remaining-time string suitable for the tray strip ("45m", "3h10m",
/// "2d4h"). Returns `None` if `at` is in the past. Mirrors Swift
/// `compactTimeRemaining`.
fn compact_time_remaining(at: chrono::DateTime<chrono::Utc>) -> Option<String> {
    let secs = at.signed_duration_since(chrono::Utc::now()).num_seconds();
    if secs <= 0 {
        return None;
    }
    let minutes = (secs / 60) % 60;
    let hours = (secs / 3600) % 24;
    let days = secs / 86_400;
    Some(if days > 0 {
        if hours > 0 { format!("{}d{}h", days, hours) } else { format!("{}d", days) }
    } else if hours > 0 {
        format!("{}h{}m", hours, minutes)
    } else {
        format!("{}m", minutes)
    })
}

/// Build the tray title shown next to the icon: "Claude · 10% (3h10m)" /
/// "Claude · 10%" / "Claude · (3h10m)" / "Claude · waiting…". Mirrors the
/// Swift `updateStatusIcon` parts-builder so labels stay terse.
fn build_tray_label(
    percent: Option<u8>,
    error: Option<&str>,
    show_percent: bool,
    countdown: Option<&str>,
) -> String {
    if let Some(err) = error {
        if percent.is_none() {
            return format!("Claude · {}", err);
        }
    }
    let mut parts: Vec<String> = Vec::with_capacity(2);
    if show_percent {
        if let Some(p) = percent {
            parts.push(format!("{}% (5h)", p));
        }
    }
    if let Some(rem) = countdown {
        parts.push(format!("({})", rem));
    }
    if parts.is_empty() {
        if percent.is_some() {
            "Claude".into()
        } else {
            "Claude · waiting…".into()
        }
    } else {
        format!("Claude · {}", parts.join(" "))
    }
}

/// Short human-readable reset time for the notification template's `{reset}`.
fn format_reset_label(at: chrono::DateTime<chrono::Utc>) -> String {
    let diff = at.signed_duration_since(chrono::Utc::now());
    let secs = diff.num_seconds();
    if secs <= 60 {
        return "soon".into();
    }
    let mins = secs / 60;
    let hours = mins / 60;
    let days = hours / 24;
    if days >= 1 {
        format!("in {}d", days)
    } else if hours >= 1 {
        format!("in {}h {}m", hours, mins % 60)
    } else {
        format!("in {}m", mins)
    }
}
