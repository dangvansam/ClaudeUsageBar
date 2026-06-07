//! Design tokens lifted from the Claude Design prototype (`project/styles.css`).
//! The egui look is built from these so the popover, settings window, and login
//! screen stay faithful to the design across light/dark themes and accent palettes.

use eframe::egui::{self, Color32, FontData, FontDefinitions, FontFamily, FontId, TextStyle, Vec2};

use crate::storage::{Accent, Settings, ThemeMode};

#[derive(Copy, Clone)]
pub struct Palette {
    // Stage / background
    pub bg_stage: Color32,
    pub bg_card: Color32,
    pub bg_card_alt: Color32,
    pub bg_inset: Color32,
    // Text
    pub text_primary: Color32,
    pub text_secondary: Color32,
    pub text_muted: Color32,
    // Borders / separators
    pub border: Color32,
    pub border_strong: Color32,
    // Interactive accent (button bg, active row, focus ring)
    pub accent: Color32,
    pub on_accent: Color32,
    // Progress-bar tiers (low → critical)
    pub lv_low: Color32,
    pub lv_mid: Color32,
    pub lv_high: Color32,
    pub lv_crit: Color32,
}

#[derive(Copy, Clone, PartialEq, Eq)]
pub enum ResolvedTheme {
    Light,
    Dark,
}

pub fn resolve(mode: ThemeMode) -> ResolvedTheme {
    match mode {
        ThemeMode::Light => ResolvedTheme::Light,
        ThemeMode::Dark => ResolvedTheme::Dark,
        ThemeMode::System => detect_system().unwrap_or(ResolvedTheme::Dark),
    }
}

#[cfg(target_os = "windows")]
fn detect_system() -> Option<ResolvedTheme> {
    use std::process::Command;
    // Reg query returns "AppsUseLightTheme    REG_DWORD    0x1" (light) or 0x0 (dark).
    let out = Command::new("reg")
        .args([
            "query",
            r"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
            "/v",
            "AppsUseLightTheme",
        ])
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    if text.contains("0x1") {
        Some(ResolvedTheme::Light)
    } else if text.contains("0x0") {
        Some(ResolvedTheme::Dark)
    } else {
        None
    }
}

#[cfg(target_os = "macos")]
fn detect_system() -> Option<ResolvedTheme> {
    use std::process::Command;
    let out = Command::new("defaults")
        .args(["read", "-g", "AppleInterfaceStyle"])
        .output()
        .ok()?;
    if out.status.success()
        && String::from_utf8_lossy(&out.stdout)
            .trim()
            .eq_ignore_ascii_case("dark")
    {
        Some(ResolvedTheme::Dark)
    } else {
        Some(ResolvedTheme::Light)
    }
}

#[cfg(target_os = "linux")]
fn detect_system() -> Option<ResolvedTheme> {
    use std::process::Command;
    let out = Command::new("gsettings")
        .args(["get", "org.gnome.desktop.interface", "color-scheme"])
        .output()
        .ok()?;
    let s = String::from_utf8_lossy(&out.stdout).to_lowercase();
    if s.contains("dark") {
        Some(ResolvedTheme::Dark)
    } else if s.contains("light") {
        Some(ResolvedTheme::Light)
    } else {
        None
    }
}

pub fn palette(theme: ResolvedTheme, accent: Accent) -> Palette {
    // Accent tier ramps, copied verbatim from project/styles.css (:root[data-accent="..."])
    let (lv_low, lv_mid, lv_high, lv_crit) = match accent {
        Accent::Warm => (
            hex(0xe0, 0xa8, 0x4a),
            hex(0xe0, 0x7f, 0x33),
            hex(0xd4, 0x58, 0x3a),
            hex(0xc3, 0x3b, 0x2c),
        ),
        Accent::Cool => (
            hex(0x36, 0xc9, 0x7a),
            hex(0xe0, 0xa1, 0x32),
            hex(0xe0, 0x61, 0x3e),
            hex(0xd2, 0x3b, 0x30),
        ),
        Accent::Coral => (
            hex(0xcf, 0x91, 0x68),
            hex(0xcd, 0x75, 0x48),
            hex(0xbd, 0x52, 0x38),
            hex(0xa8, 0x3c, 0x2a),
        ),
        Accent::Mono => (
            hex(0x9a, 0xa0, 0xa6),
            hex(0x7d, 0x83, 0x89),
            hex(0x5f, 0x65, 0x6b),
            hex(0x49, 0x4e, 0x53),
        ),
    };

    // Single interactive accent across themes (button bg, active row), per the prototype.
    let accent_int = hex(0xc8, 0x60, 0x3f);

    match theme {
        ResolvedTheme::Dark => Palette {
            bg_stage: hex(0x0e, 0x0e, 0x10),
            bg_card: hex(0x17, 0x17, 0x1a),
            bg_card_alt: hex(0x1f, 0x1f, 0x23),
            bg_inset: hex(0x12, 0x12, 0x14),
            text_primary: hex(0xf3, 0xf2, 0xee),
            text_secondary: hex(0xc1, 0xbe, 0xb6),
            text_muted: hex(0x8a, 0x87, 0x80),
            border: hex(0x2a, 0x2a, 0x2e),
            border_strong: hex(0x3a, 0x3a, 0x3e),
            accent: accent_int,
            on_accent: Color32::WHITE,
            lv_low,
            lv_mid,
            lv_high,
            lv_crit,
        },
        ResolvedTheme::Light => Palette {
            bg_stage: hex(0xe9, 0xe6, 0xe0),
            bg_card: hex(0xfa, 0xfa, 0xf7),
            bg_card_alt: hex(0xf2, 0xf0, 0xea),
            bg_inset: hex(0xee, 0xeb, 0xe3),
            text_primary: hex(0x1a, 0x1a, 0x1c),
            text_secondary: hex(0x4a, 0x47, 0x40),
            text_muted: hex(0x80, 0x7c, 0x73),
            border: hex(0xd5, 0xd0, 0xc4),
            border_strong: hex(0xbc, 0xb6, 0xa8),
            accent: accent_int,
            on_accent: Color32::WHITE,
            lv_low,
            lv_mid,
            lv_high,
            lv_crit,
        },
    }
}

#[inline]
fn hex(r: u8, g: u8, b: u8) -> Color32 {
    Color32::from_rgb(r, g, b)
}

/// Map a usage percentage to a tier color. Thresholds from `project/app.js`:
/// `>= 87 ⇒ crit`, `>= 70 ⇒ high`, `>= 45 ⇒ mid`, else `low`. Replaces the old
/// green/yellow/red ramp in line with the prototype's "less green, more orange".
pub fn tier_color(p: u8, pal: &Palette) -> Color32 {
    if p >= 87 {
        pal.lv_crit
    } else if p >= 70 {
        pal.lv_high
    } else if p >= 45 {
        pal.lv_mid
    } else {
        pal.lv_low
    }
}

/// Optional Inter font embedded from `assets/InterVariable.ttf`. Loaded once at
/// startup; falls back silently to egui's bundled font if the bytes can't be
/// parsed (e.g. someone removes the asset).
pub fn install_fonts(ctx: &egui::Context) {
    static INTER: &[u8] = include_bytes!("../../assets/InterVariable.ttf");
    let mut fonts = FontDefinitions::default();
    let inter = FontData::from_static(INTER);
    fonts.font_data.insert("Inter".into(), inter.into());
    fonts
        .families
        .entry(FontFamily::Proportional)
        .or_default()
        .insert(0, "Inter".into());
    ctx.set_fonts(fonts);
}

/// Apply the per-frame style: panel fills, widget colors, spacing, text sizes.
/// Called every frame because the user can flip theme/accent live in Settings.
pub fn apply_style(ctx: &egui::Context, pal: &Palette) {
    let mut style = (*ctx.style()).clone();

    style.spacing.item_spacing = Vec2::new(8.0, 8.0);
    style.spacing.button_padding = Vec2::new(12.0, 7.0);
    style.spacing.window_margin = egui::Margin::same(0);

    let mut v = style.visuals.clone();
    v.dark_mode = matches!(pal.text_primary, c if c.r() < 0x80);
    v.override_text_color = Some(pal.text_primary);
    v.window_fill = pal.bg_stage;
    v.panel_fill = pal.bg_stage;
    v.window_corner_radius = 14.into();
    v.window_stroke = egui::Stroke::new(1.0, pal.border);
    v.window_shadow = egui::epaint::Shadow {
        offset: [0, 8],
        blur: 24,
        spread: 0,
        color: Color32::from_black_alpha(80),
    };

    v.widgets.noninteractive.bg_fill = pal.bg_card;
    v.widgets.noninteractive.weak_bg_fill = pal.bg_card;
    v.widgets.noninteractive.bg_stroke = egui::Stroke::new(1.0, pal.border);
    v.widgets.noninteractive.fg_stroke = egui::Stroke::new(1.0, pal.text_secondary);

    v.widgets.inactive.bg_fill = pal.bg_card_alt;
    v.widgets.inactive.weak_bg_fill = pal.bg_card_alt;
    v.widgets.inactive.bg_stroke = egui::Stroke::new(1.0, pal.border);
    v.widgets.inactive.fg_stroke = egui::Stroke::new(1.0, pal.text_primary);
    v.widgets.inactive.corner_radius = 8.into();

    v.widgets.hovered.bg_fill = pal.bg_card_alt;
    v.widgets.hovered.weak_bg_fill = pal.bg_card_alt;
    v.widgets.hovered.bg_stroke = egui::Stroke::new(1.0, pal.border_strong);
    v.widgets.hovered.fg_stroke = egui::Stroke::new(1.0, pal.text_primary);
    v.widgets.hovered.corner_radius = 8.into();

    v.widgets.active.bg_fill = pal.accent;
    v.widgets.active.weak_bg_fill = pal.accent;
    v.widgets.active.bg_stroke = egui::Stroke::new(1.0, pal.accent);
    v.widgets.active.fg_stroke = egui::Stroke::new(1.5, pal.on_accent);
    v.widgets.active.corner_radius = 8.into();

    v.selection.bg_fill = pal.accent.linear_multiply(0.35);
    v.selection.stroke = egui::Stroke::new(1.0, pal.accent);
    v.hyperlink_color = pal.accent;
    v.extreme_bg_color = pal.bg_inset;
    v.faint_bg_color = pal.bg_card_alt;

    style.visuals = v;

    // Typography hierarchy that mirrors the prototype's scene-head + body sizes.
    use FontFamily::Proportional;
    style.text_styles.insert(TextStyle::Heading, FontId::new(18.0, Proportional.clone()));
    style.text_styles.insert(TextStyle::Body, FontId::new(13.0, Proportional.clone()));
    style.text_styles.insert(TextStyle::Button, FontId::new(13.0, Proportional.clone()));
    style.text_styles.insert(TextStyle::Small, FontId::new(11.0, Proportional.clone()));
    style.text_styles.insert(TextStyle::Monospace, FontId::new(12.0, FontFamily::Monospace));

    ctx.set_style(style);
}

/// Same idea applied per-render call when we need the *current* palette.
pub fn current(settings: &Settings) -> Palette {
    palette(resolve(settings.theme), settings.accent)
}
