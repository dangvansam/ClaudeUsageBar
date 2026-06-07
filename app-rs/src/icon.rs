use ab_glyph::{Font, PxScale, ScaleFont};
use once_cell::sync::Lazy;
use tiny_skia::{
    Color, FillRule, Paint, PathBuilder, Pixmap, PremultipliedColorU8, Stroke, Transform,
};

use crate::storage::{Accent, TrayIconStyle};

/// Rendered at 64px so Windows' downscale to the tray size (16–32px depending on
/// DPI) stays crisp, which matters now that we paint real font glyphs.
pub const TRAY_SIZE: u32 = 64;

/// Hack is a monospace face tuned for legibility at small sizes; reusing the
/// bytes egui already embeds means no extra font blob in the binary.
static NUM_FONT: Lazy<ab_glyph::FontRef<'static>> = Lazy::new(|| {
    ab_glyph::FontRef::try_from_slice(epaint_default_fonts::HACK_REGULAR).expect("load Hack font")
});

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum HealthTier {
    Healthy,
    Warning,
    Critical,
    Unknown,
}

impl HealthTier {
    /// Match the popover tier thresholds verbatim (project/app.js levelKey):
    /// `>= 87 ⇒ Critical`, `>= 70 ⇒ Warning`, else `Healthy`.
    pub fn from_percent(p: Option<u8>) -> Self {
        match p {
            None => Self::Unknown,
            Some(v) if v >= 87 => Self::Critical,
            Some(v) if v >= 70 => Self::Warning,
            Some(_) => Self::Healthy,
        }
    }

    fn color(self, accent: Accent) -> Color {
        let (low, mid, high, _crit) = accent_ramp(accent);
        match self {
            Self::Healthy => low,
            Self::Warning => mid,
            Self::Critical => high,
            Self::Unknown => Color::from_rgba8(0x95, 0xA5, 0xA6, 0xFF),
        }
    }
}

/// Per-accent tier ramp — same hex values as `popup/theme.rs::palette()` so the
/// tray and popover stay in sync.
fn accent_ramp(accent: Accent) -> (Color, Color, Color, Color) {
    match accent {
        Accent::Warm => (
            Color::from_rgba8(0xe0, 0xa8, 0x4a, 0xFF),
            Color::from_rgba8(0xe0, 0x7f, 0x33, 0xFF),
            Color::from_rgba8(0xd4, 0x58, 0x3a, 0xFF),
            Color::from_rgba8(0xc3, 0x3b, 0x2c, 0xFF),
        ),
        Accent::Cool => (
            Color::from_rgba8(0x36, 0xc9, 0x7a, 0xFF),
            Color::from_rgba8(0xe0, 0xa1, 0x32, 0xFF),
            Color::from_rgba8(0xe0, 0x61, 0x3e, 0xFF),
            Color::from_rgba8(0xd2, 0x3b, 0x30, 0xFF),
        ),
        Accent::Coral => (
            Color::from_rgba8(0xcf, 0x91, 0x68, 0xFF),
            Color::from_rgba8(0xcd, 0x75, 0x48, 0xFF),
            Color::from_rgba8(0xbd, 0x52, 0x38, 0xFF),
            Color::from_rgba8(0xa8, 0x3c, 0x2a, 0xFF),
        ),
        Accent::Mono => (
            Color::from_rgba8(0x9a, 0xa0, 0xa6, 0xFF),
            Color::from_rgba8(0x7d, 0x83, 0x89, 0xFF),
            Color::from_rgba8(0x5f, 0x65, 0x6b, 0xFF),
            Color::from_rgba8(0x49, 0x4e, 0x53, 0xFF),
        ),
    }
}

pub struct TrayIconBitmap {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

pub fn render_tray_icon(
    percent: Option<u8>,
    show_percent: bool,
    style: TrayIconStyle,
    accent: Accent,
) -> TrayIconBitmap {
    let size = TRAY_SIZE;
    let mut pixmap = Pixmap::new(size, size).expect("alloc pixmap");
    pixmap.fill(Color::TRANSPARENT);

    let tier = HealthTier::from_percent(percent);
    let color = tier.color(accent);
    let s = size as f32;

    // Effective style: if the user hid the percentage, fall back to Mark so the
    // tray still shows _something_, even when Number was selected.
    let effective = if matches!(style, TrayIconStyle::Number) && !show_percent {
        TrayIconStyle::Mark
    } else {
        style
    };

    match (effective, percent) {
        (TrayIconStyle::Number, Some(p)) => {
            // Compact logo + dot on the left, percent digits filling the rest.
            draw_spark(&mut pixmap, color, s * 0.17, s * 0.27, s * 0.15, s * 0.06);
            draw_status_dot(&mut pixmap, color, s * 0.17, s * 0.72, s * 0.115);
            draw_number(
                &mut pixmap,
                &p.min(100).to_string(),
                color,
                s * 0.36,
                s * 0.03,
                s * 0.62,
                s * 0.94,
            );
        }
        (TrayIconStyle::Ring, _) => {
            // Centered spark with a circular progress arc; track underneath.
            let cx = s * 0.5;
            let cy = s * 0.5;
            let r = s * 0.36;
            draw_ring_track(&mut pixmap, cx, cy, r, s * 0.085, color);
            if let Some(p) = percent {
                draw_ring_arc(&mut pixmap, cx, cy, r, s * 0.085, color, p);
            }
            draw_spark(&mut pixmap, color, cx, cy, s * 0.18, s * 0.07);
        }
        (TrayIconStyle::Mark, _) | (TrayIconStyle::Number, None) => {
            // Just the spark + status dot (the closed-state default).
            draw_spark(&mut pixmap, color, s * 0.42, s * 0.5, s * 0.30, s * 0.12);
            draw_status_dot(&mut pixmap, color, s * 0.80, s * 0.78, s * 0.16);
        }
    }

    TrayIconBitmap {
        width: size,
        height: size,
        rgba: pixmap.take(),
    }
}

/// Faded "track" circle behind the active arc — same color, reduced alpha.
fn draw_ring_track(pixmap: &mut Pixmap, cx: f32, cy: f32, r: f32, stroke_w: f32, color: Color) {
    if let Some(path) = circle_path(cx, cy, r) {
        let mut paint = Paint::default();
        let faded = Color::from_rgba(color.red(), color.green(), color.blue(), 0.22)
            .unwrap_or(color);
        paint.set_color(faded);
        paint.anti_alias = true;
        let stroke = Stroke {
            width: stroke_w,
            ..Stroke::default()
        };
        pixmap.stroke_path(&path, &paint, &stroke, Transform::identity(), None);
    }
}

/// Filled portion of the ring — uses a dashed stroke so the visible length is
/// `pct/100` of the circumference, mirroring the SVG `stroke-dashoffset` trick
/// the prototype uses.
fn draw_ring_arc(
    pixmap: &mut Pixmap,
    cx: f32,
    cy: f32,
    r: f32,
    stroke_w: f32,
    color: Color,
    pct: u8,
) {
    let path = match arc_path(cx, cy, r, pct) {
        Some(p) => p,
        None => return,
    };
    let mut paint = Paint::default();
    paint.set_color(color);
    paint.anti_alias = true;
    let stroke = Stroke {
        width: stroke_w,
        line_cap: tiny_skia::LineCap::Round,
        ..Stroke::default()
    };
    pixmap.stroke_path(&path, &paint, &stroke, Transform::identity(), None);
}

/// Build a stand-alone arc from `-π/2` clockwise for `pct/100` of the circle.
fn arc_path(cx: f32, cy: f32, r: f32, pct: u8) -> Option<tiny_skia::Path> {
    let pct = pct.min(100) as f32 / 100.0;
    if pct <= 0.0 {
        return None;
    }
    let steps = 64usize;
    let span = pct * std::f32::consts::TAU;
    let start = -std::f32::consts::FRAC_PI_2;
    let mut pb = PathBuilder::new();
    for i in 0..=steps {
        let t = i as f32 / steps as f32;
        let a = start + span * t;
        let x = cx + a.cos() * r;
        let y = cy + a.sin() * r;
        if i == 0 {
            pb.move_to(x, y);
        } else {
            pb.line_to(x, y);
        }
    }
    pb.finish()
}

/// Rasterize `text` with the Hack font, tier-colored, fitted and centered inside
/// the box (bx, by, bw, bh). Auto-scales down so 1–3 digits all fit.
fn draw_number(pixmap: &mut Pixmap, text: &str, color: Color, bx: f32, by: f32, bw: f32, bh: f32) {
    let font = &*NUM_FONT;

    let measure = |scale: f32| -> (f32, f32) {
        let sf = font.as_scaled(PxScale::from(scale));
        let w: f32 = text.chars().map(|c| sf.h_advance(font.glyph_id(c))).sum();
        (w, sf.ascent() - sf.descent())
    };

    // Shrink an initially generous scale until it fits both width and height.
    let mut scale = bh * 1.3;
    for _ in 0..10 {
        let (w, h) = measure(scale);
        let k = (bw / w).min(bh / h);
        if k >= 0.999 {
            break;
        }
        scale *= k;
    }

    let sf = font.as_scaled(PxScale::from(scale));
    let (tw, th) = measure(scale);
    let start_x = bx + (bw - tw) / 2.0;
    let baseline = by + (bh - th) / 2.0 + sf.ascent();

    let pw = pixmap.width() as i32;
    let ph = pixmap.height() as i32;
    let (cr, cg, cb) = (color.red() * 255.0, color.green() * 255.0, color.blue() * 255.0);
    let pixels = pixmap.pixels_mut();

    let mut pen = start_x;
    for c in text.chars() {
        let gid = font.glyph_id(c);
        let glyph = gid.with_scale_and_position(PxScale::from(scale), ab_glyph::point(pen, baseline));
        if let Some(outline) = font.outline_glyph(glyph) {
            let bounds = outline.px_bounds();
            outline.draw(|gx, gy, cov| {
                if cov <= 0.0 {
                    return;
                }
                let ix = bounds.min.x.round() as i32 + gx as i32;
                let iy = bounds.min.y.round() as i32 + gy as i32;
                if ix < 0 || iy < 0 || ix >= pw || iy >= ph {
                    return;
                }
                let idx = (iy * pw + ix) as usize;
                let dst = pixels[idx];
                let inv = 1.0 - cov;
                // Source-over with premultiplied alpha (the source is opaque, so
                // its premultiplied channel is colour*coverage).
                let r = (cr * cov + dst.red() as f32 * inv).round() as u8;
                let g = (cg * cov + dst.green() as f32 * inv).round() as u8;
                let b = (cb * cov + dst.blue() as f32 * inv).round() as u8;
                let a = (255.0 * cov + dst.alpha() as f32 * inv).round() as u8;
                if let Some(px) = PremultipliedColorU8::from_rgba(r, g, b, a) {
                    pixels[idx] = px;
                }
            });
        }
        pen += sf.h_advance(gid);
    }
}

fn draw_spark(pixmap: &mut Pixmap, color: Color, cx: f32, cy: f32, outer: f32, inner: f32) {
    let mut pb = PathBuilder::new();
    let arms = 4;
    let total = arms * 2;
    for i in 0..total {
        let angle = (i as f32) * std::f32::consts::PI / (arms as f32);
        let r = if i % 2 == 0 { outer } else { inner };
        let x = cx + angle.cos() * r;
        let y = cy + angle.sin() * r;
        if i == 0 {
            pb.move_to(x, y);
        } else {
            pb.line_to(x, y);
        }
    }
    pb.close();
    if let Some(path) = pb.finish() {
        let mut paint = Paint::default();
        paint.set_color(color);
        paint.anti_alias = true;
        pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
    }
}

fn draw_status_dot(pixmap: &mut Pixmap, color: Color, cx: f32, cy: f32, r: f32) {
    let outer = circle_path(cx, cy, r);
    let mut white = Paint::default();
    white.set_color(Color::WHITE);
    white.anti_alias = true;
    if let Some(p) = outer {
        pixmap.fill_path(&p, &white, FillRule::Winding, Transform::identity(), None);
    }

    let inner = circle_path(cx, cy, r * 0.7);
    let mut fill = Paint::default();
    fill.set_color(color);
    fill.anti_alias = true;
    if let Some(p) = inner {
        pixmap.fill_path(&p, &fill, FillRule::Winding, Transform::identity(), None);
    }

    let _ = Stroke::default();
}

fn circle_path(cx: f32, cy: f32, r: f32) -> Option<tiny_skia::Path> {
    let mut pb = PathBuilder::new();
    pb.push_circle(cx, cy, r);
    pb.finish()
}

pub fn render_app_icon(size: u32) -> TrayIconBitmap {
    let mut pixmap = Pixmap::new(size, size).expect("alloc pixmap");
    pixmap.fill(Color::from_rgba8(0x1A, 0x1A, 0x1A, 0xFF));
    let s = size as f32;
    let mut pb = PathBuilder::new();
    pb.move_to(s * 0.5, s * 0.18);
    pb.line_to(s * 0.62, s * 0.45);
    pb.line_to(s * 0.90, s * 0.50);
    pb.line_to(s * 0.66, s * 0.65);
    pb.line_to(s * 0.74, s * 0.90);
    pb.line_to(s * 0.5, s * 0.76);
    pb.line_to(s * 0.26, s * 0.90);
    pb.line_to(s * 0.34, s * 0.65);
    pb.line_to(s * 0.10, s * 0.50);
    pb.line_to(s * 0.38, s * 0.45);
    pb.close();
    if let Some(path) = pb.finish() {
        let mut paint = Paint::default();
        paint.set_color(Color::from_rgba8(0xF7, 0x8F, 0x3F, 0xFF));
        paint.anti_alias = true;
        pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
    }
    TrayIconBitmap {
        width: size,
        height: size,
        rgba: pixmap.take(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tier_thresholds() {
        assert_eq!(HealthTier::from_percent(None), HealthTier::Unknown);
        assert_eq!(HealthTier::from_percent(Some(0)), HealthTier::Healthy);
        assert_eq!(HealthTier::from_percent(Some(69)), HealthTier::Healthy);
        assert_eq!(HealthTier::from_percent(Some(70)), HealthTier::Warning);
        assert_eq!(HealthTier::from_percent(Some(86)), HealthTier::Warning);
        assert_eq!(HealthTier::from_percent(Some(87)), HealthTier::Critical);
    }

    #[test]
    fn renders_nonempty_bitmap() {
        let bmp = render_tray_icon(Some(42), false, TrayIconStyle::Mark, Accent::Warm);
        assert_eq!(bmp.width, TRAY_SIZE);
        assert_eq!(bmp.rgba.len(), (TRAY_SIZE * TRAY_SIZE * 4) as usize);
        assert!(bmp.rgba.iter().any(|&b| b != 0));
    }

    #[test]
    fn renders_percent_digits() {
        for p in [7u8, 42, 100] {
            let bmp = render_tray_icon(Some(p), true, TrayIconStyle::Number, Accent::Warm);
            assert_eq!(bmp.rgba.len(), (TRAY_SIZE * TRAY_SIZE * 4) as usize);
            assert!(bmp.rgba.iter().any(|&b| b != 0), "empty for {}", p);
        }
        let bmp = render_tray_icon(None, true, TrayIconStyle::Number, Accent::Warm);
        assert!(bmp.rgba.iter().any(|&b| b != 0));
    }

    #[test]
    fn renders_ring_variant() {
        for p in [0u8, 33, 87, 100] {
            let bmp = render_tray_icon(Some(p), false, TrayIconStyle::Ring, Accent::Warm);
            assert!(bmp.rgba.iter().any(|&b| b != 0), "empty ring for {}", p);
        }
    }
}
