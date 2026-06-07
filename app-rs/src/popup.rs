use chrono::{DateTime, Utc};
use eframe::egui::{
    self, Align, Color32, FontId, Layout, ProgressBar, RichText, ScrollArea, Stroke, TextEdit,
    Vec2, ViewportCommand,
};
use parking_lot::Mutex;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use crate::api::{StatusIndicator, StatusSummary, UpdateInfo, UsageSnapshot};
use crate::state::{AppState, UiCommand};
use crate::storage::Settings;

pub struct PopupApp {
    state: Arc<Mutex<AppState>>,
    cmd_tx: std::sync::mpsc::Sender<UiCommand>,
    cookie_input: String,
    cookie_dirty: bool,
    show_settings: bool,
    visible: Arc<AtomicBool>,
    last_visible: bool,
}

impl PopupApp {
    pub fn new(
        state: Arc<Mutex<AppState>>,
        cmd_tx: std::sync::mpsc::Sender<UiCommand>,
        visible: Arc<AtomicBool>,
    ) -> Self {
        let cookie = {
            let st = state.lock();
            st.cookie.clone()
        };
        Self {
            state,
            cmd_tx,
            cookie_input: cookie,
            cookie_dirty: false,
            show_settings: false,
            visible,
            last_visible: false,
        }
    }

    fn apply_theme(ctx: &egui::Context) {
        let mut style = (*ctx.style()).clone();
        style.spacing.item_spacing = Vec2::new(8.0, 10.0);
        style.spacing.button_padding = Vec2::new(12.0, 6.0);
        style.visuals = egui::Visuals::dark();
        style.visuals.window_corner_radius = 12.into();
        style.visuals.panel_fill = Color32::from_rgb(0x14, 0x14, 0x16);
        style.visuals.window_fill = Color32::from_rgb(0x14, 0x14, 0x16);
        ctx.set_style(style);
    }

    fn handle_visibility(&mut self, ctx: &egui::Context) {
        let want = self.visible.load(Ordering::SeqCst);
        if want != self.last_visible {
            if want {
                ctx.send_viewport_cmd(ViewportCommand::Visible(true));
                ctx.send_viewport_cmd(ViewportCommand::Focus);
            } else {
                ctx.send_viewport_cmd(ViewportCommand::Visible(false));
            }
            self.last_visible = want;
        }

        if ctx.input(|i| i.viewport().close_requested()) {
            self.visible.store(false, Ordering::SeqCst);
            self.last_visible = false;
            ctx.send_viewport_cmd(ViewportCommand::CancelClose);
            ctx.send_viewport_cmd(ViewportCommand::Visible(false));
        }
    }
}

impl eframe::App for PopupApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        Self::apply_theme(ctx);
        self.handle_visibility(ctx);

        let (snapshot, status, update, settings, error, loading) = {
            let st = self.state.lock();
            (
                st.usage.clone(),
                st.status.clone(),
                st.update.clone(),
                st.settings.clone(),
                st.last_error.clone(),
                st.loading,
            )
        };

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.add_space(4.0);
            header(ui, loading);
            ui.separator();

            if self.show_settings {
                settings_panel(
                    ui,
                    &mut self.show_settings,
                    &mut self.cookie_input,
                    &mut self.cookie_dirty,
                    settings,
                    &self.cmd_tx,
                );
            } else if self.cookie_input.trim().is_empty() {
                ScrollArea::vertical().show(ui, |ui| {
                    onboarding(
                        ui,
                        &mut self.cookie_input,
                        &mut self.cookie_dirty,
                        &self.cmd_tx,
                    );
                });
            } else {
                ScrollArea::vertical().show(ui, |ui| {
                    main_panel(ui, snapshot.as_ref(), status.as_ref(), error.as_deref());
                });
            }

            ui.separator();
            footer(
                ui,
                update.as_ref(),
                &mut self.show_settings,
                &self.cmd_tx,
            );
        });

        ctx.request_repaint_after(std::time::Duration::from_millis(500));
    }
}

fn header(ui: &mut egui::Ui, loading: bool) {
    ui.horizontal(|ui| {
        ui.label(RichText::new("Claude Usage").font(FontId::proportional(18.0)).strong());
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            if loading {
                ui.spinner();
                ui.label(RichText::new("Updating…").weak());
            }
        });
    });
}

fn main_panel(
    ui: &mut egui::Ui,
    snapshot: Option<&UsageSnapshot>,
    status: Option<&StatusSummary>,
    error: Option<&str>,
) {
    if let Some(err) = error {
        let banner = RichText::new(format!("⚠ {}", err)).color(Color32::from_rgb(0xE7, 0x4C, 0x3C));
        ui.label(banner);
        ui.add_space(4.0);
    }

    let Some(usage) = snapshot else {
        ui.label("Waiting for first refresh…");
        return;
    };

    usage_row(ui, "5-hour session", usage.session.utilization, usage.session.resets_at);
    usage_row(ui, "7-day window", usage.weekly.utilization, usage.weekly.resets_at);
    if let Some(sonnet) = usage.weekly_sonnet.as_ref() {
        usage_row(ui, "7-day Sonnet (Pro)", sonnet.utilization, sonnet.resets_at);
    }

    if let Some(at) = usage.fetched_at {
        ui.add_space(6.0);
        ui.label(
            RichText::new(format!("Last update: {}", format_relative(at))).weak().small(),
        );
    }

    ui.add_space(8.0);
    if let Some(st) = status {
        status_chip(ui, st);
    }
}

fn usage_row(ui: &mut egui::Ui, label: &str, percent: u8, resets_at: Option<DateTime<Utc>>) {
    let color = percent_color(percent);
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        ui.label(RichText::new(label).strong());
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            ui.label(
                RichText::new(format!("{}%", percent))
                    .color(color)
                    .font(FontId::proportional(14.0))
                    .strong(),
            );
        });
    });
    let bar = ProgressBar::new(percent as f32 / 100.0)
        .desired_width(ui.available_width())
        .fill(color);
    ui.add(bar);
    if let Some(at) = resets_at {
        ui.label(
            RichText::new(format!("Resets {}", format_relative(at)))
                .weak()
                .small(),
        );
    }
}

fn percent_color(p: u8) -> Color32 {
    if p >= 90 {
        Color32::from_rgb(0xE7, 0x4C, 0x3C)
    } else if p >= 70 {
        Color32::from_rgb(0xF1, 0xC4, 0x0F)
    } else {
        Color32::from_rgb(0x2E, 0xCC, 0x71)
    }
}

fn status_chip(ui: &mut egui::Ui, status: &StatusSummary) {
    let (bg, label) = match &status.indicator {
        StatusIndicator::None => (Color32::from_rgb(0x1E, 0x4A, 0x2A), "Operational"),
        StatusIndicator::Minor => (Color32::from_rgb(0x6A, 0x5A, 0x1E), "Minor outage"),
        StatusIndicator::Major => (Color32::from_rgb(0x6A, 0x2C, 0x1E), "Major outage"),
        StatusIndicator::Critical => (Color32::from_rgb(0x7A, 0x16, 0x16), "Critical outage"),
        StatusIndicator::Maintenance => (Color32::from_rgb(0x33, 0x33, 0x55), "Maintenance"),
        StatusIndicator::Unknown(_) => (Color32::from_rgb(0x33, 0x33, 0x33), "Unknown"),
    };
    egui::Frame::new()
        .fill(bg)
        .corner_radius(6)
        .inner_margin(egui::Margin::symmetric(10, 6))
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.label(RichText::new("●").color(Color32::WHITE));
                ui.label(RichText::new(label).color(Color32::WHITE).strong());
                ui.label(RichText::new(&status.description).color(Color32::LIGHT_GRAY).small());
            });
        });
}

fn footer(
    ui: &mut egui::Ui,
    update: Option<&UpdateInfo>,
    show_settings: &mut bool,
    tx: &std::sync::mpsc::Sender<UiCommand>,
) {
    ui.horizontal(|ui| {
        if ui.button("Refresh").clicked() {
            let _ = tx.send(UiCommand::RefreshNow);
        }
        if ui.button(if *show_settings { "← Back" } else { "⚙ Settings" }).clicked() {
            *show_settings = !*show_settings;
        }
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            if ui.button("Hide").clicked() {
                let _ = tx.send(UiCommand::HideWindow);
            }
            if let Some(u) = update {
                let label = RichText::new(format!("v{} available", u.version))
                    .color(Color32::from_rgb(0xF7, 0x8F, 0x3F));
                if ui.link(label).clicked() {
                    if let Some(url) = u.download_url() {
                        open_url(url);
                    }
                }
            }
        });
    });
}

fn onboarding(
    ui: &mut egui::Ui,
    cookie: &mut String,
    dirty: &mut bool,
    tx: &std::sync::mpsc::Sender<UiCommand>,
) {
    ui.label(
        RichText::new("Paste your Claude.ai cookie to start tracking usage.")
            .color(Color32::LIGHT_GRAY),
    );
    ui.add_space(4.0);
    ui.label(
        RichText::new(
            "How: open claude.ai in your browser → DevTools (F12) → Network tab → \
             open any /api/organizations/* request → copy the entire Cookie header.",
        )
        .small()
        .weak(),
    );
    ui.add_space(8.0);
    let edit = TextEdit::multiline(cookie)
        .desired_rows(4)
        .hint_text("Paste full Cookie header here…")
        .desired_width(ui.available_width());
    if ui.add(edit).changed() {
        *dirty = true;
    }
    ui.add_space(6.0);
    ui.horizontal(|ui| {
        let save_enabled = !cookie.trim().is_empty() && *dirty;
        let save = egui::Button::new(RichText::new("Save & fetch").strong());
        if ui.add_enabled(save_enabled, save).clicked() {
            let _ = tx.send(UiCommand::SaveCookie(cookie.trim().to_string()));
            *dirty = false;
        }
        if ui.link("Open claude.ai").clicked() {
            open_url("https://claude.ai");
        }
    });
}

fn settings_panel(
    ui: &mut egui::Ui,
    show_settings: &mut bool,
    cookie: &mut String,
    dirty: &mut bool,
    mut settings: Settings,
    tx: &std::sync::mpsc::Sender<UiCommand>,
) {
    ui.label(RichText::new("Settings").strong());
    let mut changed = false;
    changed |= ui
        .checkbox(&mut settings.usage_notifications_enabled, "Usage threshold notifications")
        .changed();
    changed |= ui
        .checkbox(&mut settings.status_notifications_enabled, "Status incident notifications")
        .changed();
    changed |= ui.checkbox(&mut settings.hotkey_enabled, "Global hotkey (Ctrl+U)").changed();
    changed |= ui.checkbox(&mut settings.launch_at_login, "Launch at login").changed();
    if changed {
        let _ = tx.send(UiCommand::UpdateSettings(settings.clone()));
    }

    ui.add_space(8.0);
    ui.label(RichText::new("Session cookie").strong());
    let edit = TextEdit::multiline(cookie)
        .desired_rows(4)
        .password(true)
        .desired_width(ui.available_width());
    if ui.add(edit).changed() {
        *dirty = true;
    }
    ui.horizontal(|ui| {
        if ui.button("Save cookie").clicked() && *dirty {
            let _ = tx.send(UiCommand::SaveCookie(cookie.trim().to_string()));
            *dirty = false;
        }
        if ui.button("Clear cookie").clicked() {
            cookie.clear();
            *dirty = false;
            let _ = tx.send(UiCommand::ClearCookie);
        }
    });

    ui.add_space(12.0);
    egui::Frame::new()
        .stroke(Stroke::new(1.0, Color32::DARK_GRAY))
        .corner_radius(6)
        .inner_margin(8)
        .show(ui, |ui| {
            ui.label(
                RichText::new("Your cookie is stored in the OS keyring (Secret Service / Credential Manager).")
                    .small()
                    .weak(),
            );
        });

    ui.add_space(8.0);
    if ui.button("Check for updates now").clicked() {
        let _ = tx.send(UiCommand::CheckUpdates);
    }
    ui.add_space(4.0);
    if ui.button("← Back").clicked() {
        *show_settings = false;
    }
}

fn format_relative(at: DateTime<Utc>) -> String {
    let now = Utc::now();
    let diff = at.signed_duration_since(now);
    let secs = diff.num_seconds();
    if secs.abs() < 60 {
        return "just now".into();
    }
    let (abs, suffix, prefix) = if secs >= 0 {
        (secs, "from now", "in ")
    } else {
        (-secs, "ago", "")
    };
    let mins = abs / 60;
    let hours = mins / 60;
    let days = hours / 24;
    if days >= 1 {
        format!("{}{}d {}", prefix, days, suffix)
    } else if hours >= 1 {
        format!("{}{}h {}m {}", prefix, hours, mins % 60, suffix)
    } else {
        format!("{}{}m {}", prefix, mins, suffix)
    }
}

fn open_url(url: &str) {
    #[cfg(target_os = "linux")]
    {
        let _ = std::process::Command::new("xdg-open").arg(url).spawn();
    }
    #[cfg(target_os = "windows")]
    {
        let _ = std::process::Command::new("cmd").args(["/c", "start", "", url]).spawn();
    }
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open").arg(url).spawn();
    }
}
