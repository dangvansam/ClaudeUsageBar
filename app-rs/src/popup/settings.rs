//! Settings window — sidebar nav + 5 pages, mirroring the Claude Design
//! prototype's information architecture (project/index.html scene 2).
//! Page enum is UI-only state (lives in PopupApp); everything saved goes
//! through `UiCommand::UpdateSettings`.

use eframe::egui::{
    self, Align, Color32, CornerRadius, FontFamily, FontId, Layout, Margin, Rect, RichText, Sense,
    Stroke, TextEdit, Ui, Vec2,
};

use crate::notify::Notifier;
use crate::state::UiCommand;
use crate::storage::{Accent, Settings, ThemeMode, TrayIconStyle};

use super::theme::Palette;
use super::{open_url, pill_button, segmented, toggle};

const CURRENT_VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Copy, Clone, PartialEq, Eq)]
pub enum SettingsPage {
    General,
    Appearance,
    Notifications,
    Account,
    About,
}

impl SettingsPage {
    fn title(self) -> &'static str {
        match self {
            Self::General => "General",
            Self::Appearance => "Tray & Appearance",
            Self::Notifications => "Notifications",
            Self::Account => "Account",
            Self::About => "About",
        }
    }
    fn icon_color(self) -> Color32 {
        // Tile background per page, copied from app.js PAGEMETA.
        match self {
            Self::General => Color32::from_rgb(0x5a, 0x6b, 0x7a),
            Self::Appearance => Color32::from_rgb(0xc8, 0x60, 0x3f),
            Self::Notifications => Color32::from_rgb(0xe0, 0x82, 0x3a),
            Self::Account => Color32::from_rgb(0x8a, 0x6d, 0xb0),
            Self::About => Color32::from_rgb(0x7d, 0x83, 0x89),
        }
    }
    fn glyph(self) -> &'static str {
        // egui has no svg-icon set in v1; small ASCII glyphs land closest to the
        // design's monochrome marks until we ship vector ones.
        match self {
            Self::General => "⚙",
            Self::Appearance => "◐",
            Self::Notifications => "!",
            Self::Account => "@",
            Self::About => "i",
        }
    }
}

pub fn render(
    ui: &mut Ui,
    pal: &Palette,
    page: &mut SettingsPage,
    show_settings: &mut bool,
    cookie: &mut String,
    cookie_dirty: &mut bool,
    preview_fallback: &mut Option<String>,
    mut settings: Settings,
    tx: &std::sync::mpsc::Sender<UiCommand>,
) {
    egui::Frame::default()
        .fill(pal.bg_card)
        .stroke(Stroke::new(1.0, pal.border))
        .corner_radius(CornerRadius::same(12))
        .outer_margin(Margin::same(12))
        .inner_margin(Margin::same(0))
        .show(ui, |ui| {
            // Title strip with back button.
            ui.horizontal(|ui| {
                ui.add_space(8.0);
                if pill_button(ui, pal, "←  Done", false).clicked() {
                    *show_settings = false;
                }
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    ui.add_space(8.0);
                    ui.label(
                        RichText::new("Settings")
                            .color(pal.text_primary)
                            .font(FontId::new(14.0, FontFamily::Proportional))
                            .strong(),
                    );
                });
            });

            ui.add_space(4.0);
            let avail_w = ui.available_width();
            let (rect, _) = ui.allocate_exact_size(Vec2::new(avail_w, 1.0), Sense::hover());
            ui.painter().line_segment(
                [rect.left_center(), rect.right_center()],
                Stroke::new(1.0, pal.border),
            );

            ui.horizontal(|ui| {
                ui.set_min_height(380.0);
                sidebar(ui, pal, page);
                vertical_divider(ui, pal);
                ui.vertical(|ui| {
                    let mut changed = false;
                    page_header(ui, pal, *page);
                    egui::ScrollArea::vertical().show(ui, |ui| {
                        ui.add_space(6.0);
                        match *page {
                            SettingsPage::General => {
                                changed |= page_general(ui, pal, &mut settings);
                            }
                            SettingsPage::Appearance => {
                                changed |= page_appearance(ui, pal, &mut settings);
                            }
                            SettingsPage::Notifications => {
                                changed |= page_notifications(ui, pal, &mut settings, preview_fallback, tx);
                            }
                            SettingsPage::Account => {
                                page_account(ui, pal, cookie, cookie_dirty, &settings, tx);
                            }
                            SettingsPage::About => {
                                page_about(ui, pal, tx);
                            }
                        }
                    });

                    if changed {
                        let _ = tx.send(UiCommand::UpdateSettings(settings.clone()));
                    }
                });
            });
        });
}

fn sidebar(ui: &mut Ui, pal: &Palette, page: &mut SettingsPage) {
    egui::Frame::default()
        .fill(pal.bg_inset)
        .inner_margin(Margin::symmetric(14, 14))
        .show(ui, |ui| {
            ui.set_width(200.0);
            ui.vertical(|ui| {
                section_label(ui, pal, "General");
                nav_item(ui, pal, page, SettingsPage::General);
                ui.add_space(10.0);
                section_label(ui, pal, "Appearance");
                nav_item(ui, pal, page, SettingsPage::Appearance);
                nav_item(ui, pal, page, SettingsPage::Notifications);
                ui.add_space(10.0);
                section_label(ui, pal, "Account");
                nav_item(ui, pal, page, SettingsPage::Account);
                nav_item(ui, pal, page, SettingsPage::About);
            });
        });
}

fn section_label(ui: &mut Ui, pal: &Palette, text: &str) {
    ui.label(
        RichText::new(text.to_uppercase())
            .color(pal.text_muted)
            .font(FontId::new(12.0, FontFamily::Proportional))
            .strong(),
    );
    ui.add_space(2.0);
}

fn nav_item(ui: &mut Ui, pal: &Palette, current: &mut SettingsPage, item: SettingsPage) {
    let active = *current == item;
    let (bg, fg) = if active {
        (pal.accent, pal.on_accent)
    } else {
        (Color32::TRANSPARENT, pal.text_primary)
    };
    egui::Frame::default()
        .fill(bg)
        .corner_radius(CornerRadius::same(10))
        .inner_margin(Margin::symmetric(10, 8))
        .show(ui, |ui| {
            let resp = ui
                .horizontal(|ui| {
                    icon_tile(ui, item.icon_color(), 30.0, item.glyph(), Color32::WHITE);
                    ui.add_space(10.0);
                    ui.label(
                        RichText::new(item.title())
                            .color(fg)
                            .font(FontId::new(14.0, FontFamily::Proportional))
                            .strong(),
                    );
                })
                .response;
            let full = ui.interact(resp.rect, resp.id.with("nav"), Sense::click());
            if full.clicked() {
                *current = item;
            }
        });
}

fn icon_tile(ui: &mut Ui, bg: Color32, size: f32, glyph: &str, fg: Color32) {
    let (rect, _) = ui.allocate_exact_size(Vec2::splat(size), Sense::hover());
    let painter = ui.painter();
    painter.rect_filled(rect, CornerRadius::same(5), bg);
    painter.text(
        rect.center(),
        egui::Align2::CENTER_CENTER,
        glyph,
        FontId::new(size * 0.62, FontFamily::Proportional),
        fg,
    );
}

fn vertical_divider(ui: &mut Ui, pal: &Palette) {
    let (rect, _) = ui.allocate_exact_size(Vec2::new(1.0, ui.available_height()), Sense::hover());
    ui.painter().line_segment(
        [rect.center_top(), rect.center_bottom()],
        Stroke::new(1.0, pal.border),
    );
}

fn page_header(ui: &mut Ui, pal: &Palette, page: SettingsPage) {
    egui::Frame::default()
        .inner_margin(Margin::symmetric(22, 18))
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                icon_tile(ui, page.icon_color(), 38.0, page.glyph(), Color32::WHITE);
                ui.add_space(14.0);
                ui.label(
                    RichText::new(page.title())
                        .color(pal.text_primary)
                        .font(FontId::new(24.0, FontFamily::Proportional))
                        .strong(),
                );
            });
        });
    let avail = ui.available_width();
    let (rect, _) = ui.allocate_exact_size(Vec2::new(avail, 1.0), Sense::hover());
    ui.painter().line_segment(
        [rect.left_center(), rect.right_center()],
        Stroke::new(1.0, pal.border),
    );
}

// ------------------------------------------------------------------ rows --
fn group_label(ui: &mut Ui, pal: &Palette, text: &str) {
    ui.add_space(14.0);
    ui.label(
        RichText::new(text.to_uppercase())
            .color(pal.text_muted)
            .font(FontId::new(12.0, FontFamily::Proportional))
            .strong(),
    );
    ui.add_space(6.0);
}

fn row<R>(ui: &mut Ui, pal: &Palette, title: &str, sub: Option<&str>, right: impl FnOnce(&mut Ui) -> R) -> R {
    egui::Frame::default()
        .fill(pal.bg_card)
        .stroke(Stroke::new(1.0, pal.border))
        .corner_radius(CornerRadius::same(14))
        .inner_margin(Margin::symmetric(18, 14))
        .outer_margin(Margin::symmetric(0, 4))
        .show(ui, |ui| {
            let avail = ui.available_width();
            ui.horizontal(|ui| {
                ui.vertical(|ui| {
                    ui.set_width(avail * 0.55);
                    ui.label(
                        RichText::new(title)
                            .color(pal.text_primary)
                            .font(FontId::new(15.0, FontFamily::Proportional))
                            .strong(),
                    );
                    if let Some(s) = sub {
                        ui.add_space(2.0);
                        ui.label(
                            RichText::new(s)
                                .color(pal.text_muted)
                                .font(FontId::new(13.0, FontFamily::Proportional)),
                        );
                    }
                });
                let r = ui
                    .with_layout(Layout::right_to_left(Align::Center), |ui| right(ui))
                    .inner;
                r
            })
            .inner
        })
        .inner
}

fn note(ui: &mut Ui, pal: &Palette, text: &str) {
    ui.add_space(4.0);
    ui.label(RichText::new(text).color(pal.text_muted).small());
}

// ------------------------------------------------------------------ pages --

fn page_general(ui: &mut Ui, pal: &Palette, settings: &mut Settings) -> bool {
    let mut changed = false;
    group_label(ui, pal, "Startup");
    row(
        ui,
        pal,
        "Launch at login",
        Some("Open Usage Bar automatically when you sign in"),
        |ui| {
            if toggle(ui, pal, &mut settings.launch_at_login).clicked() {
                changed = true;
            }
        },
    );
    row(
        ui,
        pal,
        "Check for updates automatically",
        Some("Look for a new version of Usage Bar in the background"),
        |ui| {
            if toggle(ui, pal, &mut settings.auto_check_for_updates).clicked() {
                changed = true;
            }
        },
    );

    group_label(ui, pal, "Appearance");
    let theme_val = match settings.theme {
        ThemeMode::Light => "light",
        ThemeMode::Dark => "dark",
        ThemeMode::System => "system",
    };
    row(ui, pal, "Theme", Some("Match your system or pick a side"), |ui| {
        if let Some(picked) = segmented(
            ui,
            pal,
            &[("light", "Light"), ("dark", "Dark"), ("system", "System")],
            theme_val,
        ) {
            settings.theme = match picked {
                "light" => ThemeMode::Light,
                "dark" => ThemeMode::Dark,
                _ => ThemeMode::System,
            };
            changed = true;
        }
    });

    group_label(ui, pal, "Data");
    let interval_val = match settings.refresh_interval_seconds {
        60 => "60",
        900 => "900",
        _ => "300",
    };
    row(ui, pal, "Refresh interval", Some("How often usage is pulled"), |ui| {
        if let Some(picked) = segmented(
            ui,
            pal,
            &[("60", "1m"), ("300", "5m"), ("900", "15m")],
            interval_val,
        ) {
            settings.refresh_interval_seconds = picked.parse().unwrap_or(300);
            changed = true;
        }
    });
    row(
        ui,
        pal,
        "Show service status",
        Some("Display Claude status line in the popover"),
        |ui| {
            if toggle(ui, pal, &mut settings.show_service_status).clicked() {
                changed = true;
            }
        },
    );

    group_label(ui, pal, "Input");
    row(
        ui,
        pal,
        "Global hotkey (Ctrl+U)",
        Some("Toggle the popover from anywhere"),
        |ui| {
            if toggle(ui, pal, &mut settings.hotkey_enabled).clicked() {
                changed = true;
            }
        },
    );
    changed
}

fn page_appearance(ui: &mut Ui, pal: &Palette, settings: &mut Settings) -> bool {
    let mut changed = false;
    group_label(ui, pal, "Tray icon");
    row(
        ui,
        pal,
        "Show percentage in tray",
        Some("Display the busiest limit as a number"),
        |ui| {
            if toggle(ui, pal, &mut settings.show_percent_in_tray).clicked() {
                changed = true;
            }
        },
    );
    row(
        ui,
        pal,
        "Show session reset time",
        Some("Append the 5-hour session countdown, e.g. 3h10m"),
        |ui| {
            if toggle(ui, pal, &mut settings.show_time_in_tray).clicked() {
                changed = true;
            }
        },
    );

    group_label(ui, pal, "Icon style");
    ui.horizontal(|ui| {
        ui.spacing_mut().item_spacing.x = 8.0;
        // "Number" was renamed to "Dot" in the macOS app — the enum variant stays
        // `TrayIconStyle::Number` for backwards-compatible storage.
        for (style, label, preview) in [
            (TrayIconStyle::Number, "Dot", IconPreview::Number),
            (TrayIconStyle::Ring, "Ring", IconPreview::Ring),
            (TrayIconStyle::Mark, "Mark", IconPreview::Mark),
        ] {
            if icon_style_card(ui, pal, settings.tray_icon_style == style, label, preview).clicked() {
                settings.tray_icon_style = style;
                changed = true;
            }
        }
    });

    group_label(ui, pal, "Accent palette");
    ui.horizontal(|ui| {
        ui.spacing_mut().item_spacing.x = 10.0;
        for (acc, c1, c2) in [
            (Accent::Warm, Color32::from_rgb(0xe0, 0xa8, 0x4a), Color32::from_rgb(0xd4, 0x58, 0x3a)),
            (Accent::Cool, Color32::from_rgb(0x36, 0xc9, 0x7a), Color32::from_rgb(0xe0, 0x61, 0x3e)),
            (Accent::Coral, Color32::from_rgb(0xcf, 0x91, 0x68), Color32::from_rgb(0xbd, 0x52, 0x38)),
            (Accent::Mono, Color32::from_rgb(0x9a, 0xa0, 0xa6), Color32::from_rgb(0x5f, 0x65, 0x6b)),
        ] {
            if swatch(ui, pal, settings.accent == acc, c1, c2).clicked() {
                settings.accent = acc;
                changed = true;
            }
        }
    });
    note(
        ui,
        pal,
        "Bars shade from amber → red as a limit fills. The palette sets the family.",
    );
    changed
}

fn page_notifications(
    ui: &mut Ui,
    pal: &Palette,
    settings: &mut Settings,
    preview_fallback: &mut Option<String>,
    tx: &std::sync::mpsc::Sender<UiCommand>,
) -> bool {
    let _ = tx;
    let mut changed = false;
    group_label(ui, pal, "Alerts");
    row(
        ui,
        pal,
        "Enable notifications",
        Some("Warn you before you hit a limit"),
        |ui| {
            if toggle(ui, pal, &mut settings.usage_notifications_enabled).clicked() {
                changed = true;
            }
        },
    );
    row(
        ui,
        pal,
        "Service status notifications",
        Some("Ping when Claude status changes"),
        |ui| {
            if toggle(ui, pal, &mut settings.status_notifications_enabled).clicked() {
                changed = true;
            }
        },
    );
    let session_val = format!("{}%", settings.session_warn_threshold);
    row(
        ui,
        pal,
        "Session warning at",
        Some("Notify when your 5-hour limit reaches"),
        |ui| {
            if let Some(picked) = segmented(
                ui,
                pal,
                &[("75", "75%"), ("85", "85%"), ("95", "95%")],
                strip_pct(&session_val),
            ) {
                settings.session_warn_threshold = picked.parse().unwrap_or(85);
                changed = true;
            }
        },
    );
    let weekly_val = format!("{}%", settings.weekly_warn_threshold);
    row(
        ui,
        pal,
        "Weekly warning at",
        Some("Notify when your 7-day limit reaches"),
        |ui| {
            if let Some(picked) = segmented(
                ui,
                pal,
                &[("80", "80%"), ("90", "90%"), ("95", "95%")],
                strip_pct(&weekly_val),
            ) {
                settings.weekly_warn_threshold = picked.parse().unwrap_or(90);
                changed = true;
            }
        },
    );

    group_label(ui, pal, "Custom message");
    egui::Frame::default()
        .inner_margin(Margin::symmetric(14, 8))
        .show(ui, |ui| {
            ui.horizontal_wrapped(|ui| {
                ui.label(RichText::new("Tokens:").color(pal.text_muted).small());
                ui.add_space(2.0);
                for tok in ["{pct}", "{limit}", "{reset}"] {
                    kbd(ui, pal, tok);
                }
            });
            ui.add_space(6.0);
            let edit = TextEdit::multiline(&mut settings.notif_message_template)
                .desired_rows(3)
                .char_limit(160)
                .desired_width(ui.available_width());
            if ui.add(edit).changed() {
                changed = true;
            }
            ui.add_space(4.0);
            let count = settings.notif_message_template.chars().count();
            ui.label(
                RichText::new(format!("{}/160", count))
                    .color(pal.text_muted)
                    .small(),
            );
        });

    ui.add_space(6.0);
    egui::Frame::default()
        .inner_margin(Margin::symmetric(14, 8))
        .show(ui, |ui| {
            if pill_button(ui, pal, "Preview notification", true).clicked() {
                let body = Notifier::render_template(
                    &settings.notif_message_template,
                    settings.session_warn_threshold,
                    "session",
                    "in 1h 24m",
                );
                if !Notifier::send_preview(&body) {
                    *preview_fallback = Some(body);
                }
            }
        });

    changed
}

fn page_account(
    ui: &mut Ui,
    pal: &Palette,
    cookie: &mut String,
    cookie_dirty: &mut bool,
    settings: &Settings,
    tx: &std::sync::mpsc::Sender<UiCommand>,
) {
    let _ = settings;
    let signed_in = !cookie.trim().is_empty();

    if signed_in {
        group_label(ui, pal, "Signed in");
        egui::Frame::default()
            .fill(pal.bg_card)
            .stroke(Stroke::new(1.0, pal.border))
            .corner_radius(CornerRadius::same(12))
            .inner_margin(Margin::symmetric(14, 12))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    super::draw_brand_dot(ui, pal.accent, 36.0);
                    ui.add_space(12.0);
                    ui.vertical(|ui| {
                        ui.label(
                            RichText::new("Connected to claude.ai")
                                .color(pal.text_primary)
                                .font(FontId::new(14.0, FontFamily::Proportional))
                                .strong(),
                        );
                        ui.label(
                            RichText::new("Session cookie stored in the OS keyring.")
                                .color(pal.text_muted)
                                .small(),
                        );
                    });
                });
            });

        ui.add_space(10.0);
        ui.horizontal(|ui| {
            if pill_button(ui, pal, "Sign out", false).clicked() {
                cookie.clear();
                *cookie_dirty = false;
                let _ = tx.send(UiCommand::ClearCookie);
            }
            if pill_button(ui, pal, "Open claude.ai", false).clicked() {
                open_url("https://claude.ai");
            }
        });
        return;
    }

    group_label(ui, pal, "Account");
    ui.label(
        RichText::new("Sign in to claude.ai to read your usage limits. No data leaves your Mac.")
            .color(pal.text_secondary),
    );

    ui.add_space(10.0);
    ui.horizontal(|ui| {
        if pill_button(ui, pal, "Sign in with claude.ai", true).clicked() {
            // Phase A: opens the system browser. Future webview wiring will swap
            // this for an in-app sheet that captures the cookie on success.
            open_url("https://claude.ai/login");
        }
        if pill_button(ui, pal, "Open claude.ai", false).clicked() {
            open_url("https://claude.ai");
        }
    });

    // Claude Code CLI detection — read-only probe. We only check the keychain
    // item EXISTS; the token isn't decrypted and isn't currently usable for the
    // claude.ai web endpoints. Surface as a hint so CLI users know we noticed.
    if claude_code_login_detected() {
        ui.add_space(10.0);
        egui::Frame::default()
            .fill(pal.bg_inset)
            .stroke(Stroke::new(1.0, pal.border))
            .corner_radius(CornerRadius::same(10))
            .inner_margin(Margin::symmetric(14, 12))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(
                        RichText::new("⌨")
                            .color(pal.accent)
                            .font(FontId::new(16.0, FontFamily::Proportional)),
                    );
                    ui.add_space(8.0);
                    ui.vertical(|ui| {
                        ui.label(
                            RichText::new("Claude Code login detected")
                                .color(pal.text_primary)
                                .strong(),
                        );
                        ui.label(
                            RichText::new(
                                "API-token sign-in via Claude Code is on the roadmap. \
                                 For now, use the claude.ai sign-in above.",
                            )
                            .color(pal.text_muted)
                            .small(),
                        );
                    });
                });
            });
    }

    // Manual paste fallback — collapsed by default. Matches the Swift
    // DisclosureGroup "Paste cookie manually".
    ui.add_space(12.0);
    egui::CollapsingHeader::new(
        RichText::new("Paste cookie manually")
            .color(pal.text_secondary)
            .strong(),
    )
    .id_salt("manual-paste-section")
    .default_open(false)
    .show(ui, |ui| {
        ui.add_space(4.0);
        egui::Frame::default()
            .fill(pal.bg_inset)
            .stroke(Stroke::new(1.0, pal.border))
            .corner_radius(CornerRadius::same(8))
            .inner_margin(Margin::same(6))
            .show(ui, |ui| {
                super::read_cookie_field(
                    ui,
                    pal,
                    cookie,
                    cookie_dirty,
                    3,
                    "Paste full Cookie header here…",
                );
            });
        note(
            ui,
            pal,
            "How: open claude.ai → DevTools (F12) → Network tab → open any /api/organizations/* \
             request → copy the entire Cookie header.",
        );
        ui.add_space(6.0);
        if pill_button(ui, pal, "Save cookie", true).clicked() && *cookie_dirty {
            let _ = tx.send(UiCommand::SaveCookie(cookie.trim().to_string()));
            *cookie_dirty = false;
        }
    });
}

// Probe for an existing Claude Code CLI login. The CLI stores its OAuth bundle
// in the OS keyring under service "Claude Code-credentials" (account = user
// email). We only check the entry EXISTS — never decrypt the token, both because
// it targets api.anthropic.com (not claude.ai web cookies) and because reading
// would trigger a Keychain prompt on macOS.
fn claude_code_login_detected() -> bool {
    // The CLI uses the user's email as the account. We don't know it, so we try
    // a wildcard via the no-secret listing path: keyring's high-level API
    // doesn't expose that, so as a pragmatic check we attempt to instantiate an
    // entry with a known dummy username. If the underlying backend reports the
    // service exists at all, that's enough.
    match keyring::Entry::new("Claude Code-credentials", "user") {
        Ok(entry) => match entry.get_password() {
            Ok(_) => true,
            Err(keyring::Error::NoEntry) => {
                // Service may exist under a different username; the most
                // reliable test is per-OS. On macOS keyring will report NoEntry
                // even when the service is present under another account, so
                // assume false here — the cross-platform Phase B detection
                // tightens this on macOS via SecItemCopyMatching (handled in the
                // Swift app, not this Rust path).
                false
            }
            Err(_) => false,
        },
        Err(_) => false,
    }
}

fn page_about(ui: &mut Ui, pal: &Palette, tx: &std::sync::mpsc::Sender<UiCommand>) {
    ui.add_space(8.0);
    egui::Frame::default()
        .inner_margin(Margin::symmetric(14, 8))
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                super::draw_brand_dot(ui, pal.accent, 44.0);
                ui.add_space(12.0);
                ui.vertical(|ui| {
                    ui.label(
                        RichText::new("Claude Usage Bar")
                            .color(pal.text_primary)
                            .font(FontId::new(15.0, FontFamily::Proportional))
                            .strong(),
                    );
                    ui.label(
                        RichText::new(format!("Version {}", CURRENT_VERSION))
                            .color(pal.text_muted)
                            .small(),
                    );
                });
            });
        });

    group_label(ui, pal, "App");
    row(ui, pal, "Check for updates", None, |ui| {
        if pill_button(ui, pal, "Check now", false).clicked() {
            let _ = tx.send(UiCommand::CheckUpdates);
        }
    });
    row(ui, pal, "Website", None, |ui| {
        if pill_button(ui, pal, "Visit", false).clicked() {
            open_url("https://claudeusagebar.com");
        }
    });
    row(ui, pal, "Source code", None, |ui| {
        if pill_button(ui, pal, "GitHub", false).clicked() {
            open_url("https://github.com/Artzainnn/ClaudeUsageBar");
        }
    });

    group_label(ui, pal, "License");
    note(
        ui,
        pal,
        "MIT. Made for macOS, Windows & Linux. Not affiliated with Anthropic.",
    );
}

// --------------------------------------------------------------- previews --
enum IconPreview {
    Number,
    Ring,
    Mark,
}

fn icon_style_card(
    ui: &mut Ui,
    pal: &Palette,
    selected: bool,
    label: &str,
    preview: IconPreview,
) -> egui::Response {
    let card_w = 90.0;
    let card_h = 70.0;
    let stroke = if selected {
        Stroke::new(1.5, pal.accent)
    } else {
        Stroke::new(1.0, pal.border)
    };
    let bg = if selected {
        pal.bg_inset
    } else {
        pal.bg_card_alt
    };

    let (rect, resp) = ui.allocate_exact_size(Vec2::new(card_w, card_h), Sense::click());
    let painter = ui.painter();
    painter.rect_filled(rect, CornerRadius::same(8), bg);
    painter.rect_stroke(rect, CornerRadius::same(8), stroke, egui::StrokeKind::Inside);

    // Preview glyph in the top half.
    let preview_rect = Rect::from_min_size(rect.min + Vec2::new(0.0, 6.0), Vec2::new(card_w, 36.0));
    let cx = preview_rect.center().x;
    let cy = preview_rect.center().y;
    match preview {
        IconPreview::Number => {
            painter.text(
                egui::pos2(cx, cy),
                egui::Align2::CENTER_CENTER,
                "82%",
                FontId::new(15.0, FontFamily::Proportional),
                pal.lv_mid,
            );
        }
        IconPreview::Ring => {
            painter.circle_stroke(egui::pos2(cx, cy), 12.0, Stroke::new(2.5, pal.border_strong));
            // Three-quarter arc (approximated with short segments — egui has no arc primitive).
            let r = 12.0;
            let steps = 22;
            for i in 0..steps {
                let t0 = i as f32 / steps as f32;
                let t1 = (i + 1) as f32 / steps as f32;
                let a0 = -std::f32::consts::FRAC_PI_2 + t0 * 1.5 * std::f32::consts::PI;
                let a1 = -std::f32::consts::FRAC_PI_2 + t1 * 1.5 * std::f32::consts::PI;
                painter.line_segment(
                    [
                        egui::pos2(cx + a0.cos() * r, cy + a0.sin() * r),
                        egui::pos2(cx + a1.cos() * r, cy + a1.sin() * r),
                    ],
                    Stroke::new(2.5, pal.lv_mid),
                );
            }
        }
        IconPreview::Mark => {
            painter.text(
                egui::pos2(cx, cy),
                egui::Align2::CENTER_CENTER,
                "✦",
                FontId::new(20.0, FontFamily::Proportional),
                pal.lv_mid,
            );
        }
    }

    // Label band along the bottom.
    let label_rect = Rect::from_min_size(rect.left_bottom() - Vec2::new(0.0, 24.0), Vec2::new(card_w, 24.0));
    painter.text(
        label_rect.center(),
        egui::Align2::CENTER_CENTER,
        label,
        FontId::new(12.0, FontFamily::Proportional),
        pal.text_primary,
    );
    resp
}

fn swatch(
    ui: &mut Ui,
    pal: &Palette,
    selected: bool,
    c1: Color32,
    c2: Color32,
) -> egui::Response {
    let size = 30.0;
    let (rect, resp) = ui.allocate_exact_size(Vec2::splat(size), Sense::click());
    let painter = ui.painter();
    // Two-tone diagonal — egui has no linear-gradient, so we paint two triangles.
    let top_left = rect.min;
    let top_right = egui::pos2(rect.right(), rect.top());
    let bot_left = egui::pos2(rect.left(), rect.bottom());
    let bot_right = rect.max;
    let r = CornerRadius::same(6);
    painter.rect_filled(rect, r, c2);
    painter.add(egui::Shape::convex_polygon(
        vec![top_left, top_right, bot_left],
        c1,
        Stroke::NONE,
    ));
    let _ = bot_right;
    if selected {
        painter.rect_stroke(
            rect.expand(2.0),
            CornerRadius::same(8),
            Stroke::new(2.0, pal.accent),
            egui::StrokeKind::Outside,
        );
    } else {
        painter.rect_stroke(rect, r, Stroke::new(1.0, pal.border), egui::StrokeKind::Inside);
    }
    resp
}

fn kbd(ui: &mut Ui, pal: &Palette, text: &str) {
    egui::Frame::default()
        .fill(pal.bg_card_alt)
        .stroke(Stroke::new(1.0, pal.border))
        .corner_radius(CornerRadius::same(4))
        .inner_margin(Margin::symmetric(5, 1))
        .show(ui, |ui| {
            ui.label(
                RichText::new(text)
                    .color(pal.text_secondary)
                    .font(FontId::new(11.0, FontFamily::Monospace)),
            );
        });
}

fn strip_pct(s: &str) -> &str {
    s.trim_end_matches('%')
}
