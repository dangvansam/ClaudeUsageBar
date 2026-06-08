//! Popup window — translates the Claude Design prototype's three primary
//! surfaces (popover, settings, welcome) into egui. Theme tokens, palette, and
//! tier ramps live in `theme`; settings pages in `settings`; the empty-cookie
//! welcome card in `login`. Per-frame rendering routes to one of the three
//! based on UI state.

mod login;
mod settings;
mod theme;

use chrono::{DateTime, Utc};
use eframe::egui::{
    self, Align, Color32, CornerRadius, FontFamily, FontId, Layout, Margin, Rect, Response,
    RichText, Sense, Stroke, TextEdit, Ui, Vec2, ViewportCommand,
};
use parking_lot::Mutex;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use crate::api::{StatusIndicator, StatusSummary, UpdateInfo, UsageSnapshot};
use crate::state::{AppState, UiCommand};

use self::settings::SettingsPage;
use self::theme::Palette;

pub struct PopupApp {
    state: Arc<Mutex<AppState>>,
    cmd_tx: std::sync::mpsc::Sender<UiCommand>,
    cookie_input: String,
    cookie_dirty: bool,
    show_settings: bool,
    last_show_settings: bool,
    settings_page: SettingsPage,
    visible: Arc<AtomicBool>,
    last_visible: bool,
    fonts_installed: bool,
    // Set when the Preview button could not deliver a notification — the parent
    // renders a modal-style window with the body text + "Open System Settings"
    // link so the user can re-enable banners. Mirrors Swift's NSAlert fallback.
    notif_preview_fallback: Option<String>,
    on_frame: Option<Box<dyn FnMut(&egui::Context)>>,
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
            last_show_settings: false,
            settings_page: SettingsPage::General,
            notif_preview_fallback: None,
            visible,
            last_visible: false,
            fonts_installed: false,
            on_frame: None,
        }
    }

    pub fn with_frame_hook(mut self, hook: Box<dyn FnMut(&egui::Context)>) -> Self {
        self.on_frame = Some(hook);
        self
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
        if let Some(hook) = self.on_frame.as_mut() {
            hook(ctx);
        }
        if !self.fonts_installed {
            theme::install_fonts(ctx);
            self.fonts_installed = true;
        }
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

        let pal = theme::current(&settings);
        theme::apply_style(ctx, &pal);

        // Settings is a much bigger surface than the popover meters; resize the
        // viewport on enter/leave so each view gets its own appropriate window
        // size. Mirrors the macOS app where settings opens a separate 920x680
        // NSWindow while the popover stays at 440x ~ measured.
        if self.show_settings != self.last_show_settings {
            let new_size = if self.show_settings {
                egui::vec2(920.0, 680.0)
            } else {
                egui::vec2(440.0, 500.0)
            };
            ctx.send_viewport_cmd(ViewportCommand::InnerSize(new_size));
            self.last_show_settings = self.show_settings;
        }

        egui::CentralPanel::default()
            .frame(egui::Frame::default().fill(pal.bg_stage).inner_margin(Margin::same(0)))
            .show(ctx, |ui| {
                let avail_w = ui.available_width();
                if self.show_settings {
                    settings::render(
                        ui,
                        &pal,
                        &mut self.settings_page,
                        &mut self.show_settings,
                        &mut self.cookie_input,
                        &mut self.cookie_dirty,
                        &mut self.notif_preview_fallback,
                        settings,
                        &self.cmd_tx,
                    );
                } else if self.cookie_input.trim().is_empty() {
                    login::render(
                        ui,
                        &pal,
                        avail_w,
                        &mut self.cookie_input,
                        &mut self.cookie_dirty,
                        &self.cmd_tx,
                    );
                } else {
                    main_panel(
                        ui,
                        &pal,
                        snapshot.as_ref(),
                        status.as_ref(),
                        update.as_ref(),
                        error.as_deref(),
                        loading,
                        settings.show_service_status,
                        &mut self.show_settings,
                        &self.cmd_tx,
                    );
                }
            });

        // Floating fallback for the Notification Preview when delivery is
        // rejected by the OS — same "open System Settings" affordance as Swift's
        // NSAlert fallback so the button is never silent.
        if let Some(body) = self.notif_preview_fallback.clone() {
            let mut dismiss = false;
            egui::Window::new("Notification preview")
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
                .show(ctx, |ui| {
                    ui.label(
                        egui::RichText::new("Could not deliver notification")
                            .color(pal.text_primary)
                            .strong(),
                    );
                    ui.add_space(6.0);
                    ui.label(egui::RichText::new(&body).color(pal.text_secondary));
                    ui.add_space(4.0);
                    ui.label(
                        egui::RichText::new(
                            "Notifications for Claude Usage Bar appear to be disabled at the OS level.",
                        )
                        .color(pal.text_muted)
                        .small(),
                    );
                    ui.add_space(10.0);
                    ui.horizontal(|ui| {
                        if pill_button(ui, &pal, "Open System Settings", true).clicked() {
                            crate::notify::Notifier::open_system_notification_settings();
                            dismiss = true;
                        }
                        if pill_button(ui, &pal, "Dismiss", false).clicked() {
                            dismiss = true;
                        }
                    });
                });
            if dismiss {
                self.notif_preview_fallback = None;
            }
        }

        let interval = if self.on_frame.is_some() { 80 } else { 500 };
        ctx.request_repaint_after(std::time::Duration::from_millis(interval));
    }
}

/// Scene 1 (popover): brand row + progress meters + status + footer.
/// Width is driven by the window; the prototype targets ~320px content width.
fn main_panel(
    ui: &mut Ui,
    pal: &Palette,
    snapshot: Option<&UsageSnapshot>,
    status: Option<&StatusSummary>,
    update: Option<&UpdateInfo>,
    error: Option<&str>,
    loading: bool,
    show_service_status: bool,
    show_settings: &mut bool,
    tx: &std::sync::mpsc::Sender<UiCommand>,
) {
    egui::Frame::default()
        .fill(pal.bg_card)
        .stroke(Stroke::new(1.0, pal.border))
        .corner_radius(CornerRadius::same(12))
        .inner_margin(Margin::symmetric(14, 14))
        .outer_margin(Margin::same(12))
        .show(ui, |ui| {
            ui.set_min_width(300.0);

            // Title row: brand mark + name + spinner.
            ui.horizontal(|ui| {
                draw_brand_dot(ui, pal.accent, 22.0);
                ui.add_space(8.0);
                ui.label(
                    RichText::new("Claude Usage")
                        .color(pal.text_primary)
                        .font(FontId::new(15.0, FontFamily::Proportional))
                        .strong(),
                );
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if loading {
                        ui.add(egui::Spinner::new().size(13.0));
                        ui.label(
                            RichText::new("Updating…")
                                .color(pal.text_muted)
                                .small(),
                        );
                    }
                });
            });

            ui.add_space(12.0);

            if let Some(err) = error {
                ui.add_space(2.0);
                ui.label(
                    RichText::new(format!("⚠  {}", err))
                        .color(pal.lv_crit)
                        .small(),
                );
                ui.add_space(8.0);
            }

            match snapshot {
                None => {
                    ui.label(
                        RichText::new("Waiting for first refresh…")
                            .color(pal.text_secondary),
                    );
                }
                Some(usage) => {
                    meter(ui, pal, "Session (5 hour)", usage.session.utilization, usage.session.resets_at, false);
                    ui.add_space(10.0);
                    meter(ui, pal, "Weekly (7 day)", usage.weekly.utilization, usage.weekly.resets_at, true);
                    if let Some(sonnet) = usage.weekly_sonnet.as_ref() {
                        ui.add_space(10.0);
                        meter(ui, pal, "Sonnet (Pro · 7 day)", sonnet.utilization, sonnet.resets_at, true);
                    }
                }
            }

            // Status row is opt-in via Settings → General → Show service status,
            // matching the Swift `showServiceStatus` toggle.
            if show_service_status {
                if let Some(st) = status {
                    ui.add_space(12.0);
                    divider(ui, pal);
                    ui.add_space(8.0);
                    status_row(ui, pal, st);
                }
            }

            ui.add_space(12.0);
            divider(ui, pal);
            ui.add_space(8.0);

            ui.horizontal(|ui| {
                let last_label = snapshot
                    .and_then(|u| u.fetched_at.map(format_relative_short))
                    .unwrap_or_else(|| "—".to_string());
                ui.label(
                    RichText::new(format!("Last updated: {}", last_label))
                        .color(pal.text_muted)
                        .small(),
                );
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if pill_button(ui, pal, "Refresh", false).clicked() {
                        let _ = tx.send(UiCommand::RefreshNow);
                    }
                });
            });

            ui.add_space(8.0);

            ui.horizontal(|ui| {
                if pill_button(ui, pal, "⚙  Settings", false).clicked() {
                    *show_settings = true;
                }
                if let Some(u) = update {
                    ui.add_space(6.0);
                    let label = RichText::new(format!("↥ v{} available", u.version))
                        .color(pal.lv_high);
                    if ui.link(label).clicked() {
                        if let Some(url) = u.download_url() {
                            open_url(url);
                        }
                    }
                }
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if pill_button(ui, pal, "Hide", true).clicked() {
                        let _ = tx.send(UiCommand::HideWindow);
                    }
                });
            });
        });
}

fn meter(
    ui: &mut Ui,
    pal: &Palette,
    name: &str,
    pct: u8,
    resets_at: Option<DateTime<Utc>>,
    include_date: bool,
) {
    let color = theme::tier_color(pct, pal);

    ui.horizontal(|ui| {
        ui.label(
            RichText::new(name)
                .color(pal.text_primary)
                .strong(),
        );
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            if let Some(at) = resets_at {
                ui.label(
                    RichText::new(format_meter_reset(at, include_date))
                        .color(pal.text_muted)
                        .small(),
                );
            }
        });
    });
    ui.add_space(4.0);

    // Custom rounded progress track (egui's stock ProgressBar can't take the
    // pill shape + tier color the design calls for).
    let track_h = 8.0;
    let (rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), track_h), Sense::hover());
    let painter = ui.painter();
    painter.rect_filled(rect, CornerRadius::same(4), pal.bg_inset);
    let frac = (pct as f32 / 100.0).clamp(0.0, 1.0);
    if frac > 0.0 {
        let fill_rect = Rect::from_min_size(
            rect.min,
            Vec2::new(rect.width() * frac, rect.height()),
        );
        painter.rect_filled(fill_rect, CornerRadius::same(4), color);
    }

    ui.add_space(4.0);
    ui.label(
        RichText::new(format!("{}% used", pct))
            .color(color)
            .small()
            .strong(),
    );
}

fn status_row(ui: &mut Ui, pal: &Palette, status: &StatusSummary) {
    let (dot, label) = match &status.indicator {
        StatusIndicator::None => (Color32::from_rgb(0x35, 0xc4, 0x6b), "All Claude services operational"),
        StatusIndicator::Minor => (pal.lv_mid, status.description.as_str()),
        StatusIndicator::Major => (pal.lv_high, status.description.as_str()),
        StatusIndicator::Critical => (pal.lv_crit, status.description.as_str()),
        StatusIndicator::Maintenance => (pal.text_secondary, "Maintenance"),
        StatusIndicator::Unknown(_) => (pal.text_muted, "Status unknown"),
    };
    ui.horizontal(|ui| {
        ui.label(RichText::new("●").color(dot).small());
        ui.label(RichText::new(label).color(pal.text_secondary).small());
    });
}

fn divider(ui: &mut Ui, pal: &Palette) {
    let (rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 1.0), Sense::hover());
    ui.painter().line_segment(
        [rect.left_center(), rect.right_center()],
        Stroke::new(1.0, pal.border),
    );
}

pub(crate) fn draw_brand_dot(ui: &mut Ui, accent: Color32, size: f32) {
    let (rect, _) = ui.allocate_exact_size(Vec2::splat(size), Sense::hover());
    let painter = ui.painter();
    painter.rect_filled(rect, CornerRadius::same((size * 0.27) as u8), accent);

    // 4-pointed spark inside the rounded tile.
    let cx = rect.center().x;
    let cy = rect.center().y;
    let outer = size * 0.30;
    let inner = size * 0.11;
    let mut pts = Vec::with_capacity(8);
    for i in 0..8 {
        let angle = (i as f32) * std::f32::consts::PI / 4.0;
        let r = if i % 2 == 0 { outer } else { inner };
        pts.push(egui::pos2(cx + angle.cos() * r, cy + angle.sin() * r));
    }
    painter.add(egui::Shape::convex_polygon(
        pts,
        Color32::WHITE,
        Stroke::NONE,
    ));
}

pub(crate) fn pill_button(ui: &mut Ui, pal: &Palette, label: &str, primary: bool) -> Response {
    let (bg, fg, border) = if primary {
        (pal.accent, pal.on_accent, pal.accent)
    } else {
        (pal.bg_card_alt, pal.text_primary, pal.border)
    };
    let text = RichText::new(label).color(fg);
    let btn = egui::Button::new(text)
        .fill(bg)
        .stroke(Stroke::new(1.0, border))
        .corner_radius(CornerRadius::same(8))
        .min_size(Vec2::new(0.0, 28.0));
    ui.add(btn)
}

pub(crate) fn segmented<'a>(
    ui: &mut Ui,
    pal: &Palette,
    options: &'a [(&'a str, &'a str)],
    current: &str,
) -> Option<&'a str> {
    let mut picked: Option<&'a str> = None;
    egui::Frame::default()
        .fill(pal.bg_inset)
        .corner_radius(CornerRadius::same(8))
        .inner_margin(Margin::same(2))
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 2.0;
                for (val, label) in options {
                    let active = *val == current;
                    let (bg, fg) = if active {
                        (pal.accent, pal.on_accent)
                    } else {
                        (Color32::TRANSPARENT, pal.text_secondary)
                    };
                    let resp = ui.add(
                        egui::Button::new(RichText::new(*label).color(fg))
                            .fill(bg)
                            .stroke(Stroke::NONE)
                            .corner_radius(CornerRadius::same(6))
                            .min_size(Vec2::new(0.0, 22.0)),
                    );
                    if resp.clicked() {
                        picked = Some(*val);
                    }
                }
            });
        });
    picked
}

pub(crate) fn toggle(ui: &mut Ui, pal: &Palette, on: &mut bool) -> Response {
    let desired = Vec2::new(36.0, 20.0);
    let (rect, resp) = ui.allocate_exact_size(desired, Sense::click());
    if resp.clicked() {
        *on = !*on;
    }
    let painter = ui.painter();
    let track_color = if *on { pal.accent } else { pal.bg_inset };
    painter.rect_filled(rect, CornerRadius::same(10), track_color);
    painter.rect_stroke(
        rect,
        CornerRadius::same(10),
        Stroke::new(1.0, pal.border),
        egui::StrokeKind::Inside,
    );
    let r = (rect.height() - 4.0) / 2.0;
    let cx = if *on {
        rect.right() - 2.0 - r
    } else {
        rect.left() + 2.0 + r
    };
    painter.circle_filled(egui::pos2(cx, rect.center().y), r, Color32::WHITE);
    resp
}

pub(crate) fn read_cookie_field(
    ui: &mut Ui,
    pal: &Palette,
    cookie: &mut String,
    dirty: &mut bool,
    rows: usize,
    placeholder: &str,
) {
    let _ = pal;
    let edit = TextEdit::multiline(cookie)
        .desired_rows(rows)
        .hint_text(placeholder)
        .password(true)
        .desired_width(ui.available_width());
    if ui.add(edit).changed() {
        *dirty = true;
    }
}

/// Swift-parity reset label: "Resets at 19:20 · in 3h 10m" for a session, or
/// "Resets on 13/06 at 21:00 · in 5d 3h 55m" for the weekly limits. Pulls the
/// local date/time and a long-form remaining string. Returns just the absolute
/// half if the date is in the past.
fn format_meter_reset(at: DateTime<Utc>, include_date: bool) -> String {
    use chrono::Local;
    let local = at.with_timezone(&Local);
    let base = if include_date {
        format!("Resets on {} at {}", local.format("%d/%m"), local.format("%H:%M"))
    } else {
        format!("Resets at {}", local.format("%H:%M"))
    };
    let secs = at.signed_duration_since(Utc::now()).num_seconds();
    if secs <= 0 {
        return base;
    }
    let minutes = (secs / 60) % 60;
    let hours = (secs / 3600) % 24;
    let days = secs / 86_400;
    let rem = if days > 0 {
        if hours > 0 {
            format!("{}d {}h {}m", days, hours, minutes)
        } else {
            format!("{}d {}m", days, minutes)
        }
    } else if hours > 0 {
        format!("{}h {}m", hours, minutes)
    } else {
        format!("{}m", minutes)
    };
    format!("{} · in {}", base, rem)
}

fn format_relative_short(at: DateTime<Utc>) -> String {
    let now = Utc::now();
    let diff = at.signed_duration_since(now);
    let secs = diff.num_seconds();
    if secs.abs() < 60 {
        return "just now".into();
    }
    let (abs, suffix, prefix) = if secs >= 0 {
        (secs, "", "in ")
    } else {
        (-secs, " ago", "")
    };
    let mins = abs / 60;
    let hours = mins / 60;
    let days = hours / 24;
    if days >= 1 {
        format!("{}{}d{}", prefix, days, suffix)
    } else if hours >= 1 {
        format!("{}{}h {}m{}", prefix, hours, mins % 60, suffix)
    } else {
        format!("{}{}m{}", prefix, mins, suffix)
    }
}

pub(crate) fn open_url(url: &str) {
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
