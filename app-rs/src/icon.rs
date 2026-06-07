use tiny_skia::{Color, FillRule, Paint, PathBuilder, Pixmap, Stroke, Transform};

pub const TRAY_SIZE: u32 = 32;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum HealthTier {
    Healthy,
    Warning,
    Critical,
    Unknown,
}

impl HealthTier {
    pub fn from_percent(p: Option<u8>) -> Self {
        match p {
            None => Self::Unknown,
            Some(v) if v >= 90 => Self::Critical,
            Some(v) if v >= 70 => Self::Warning,
            Some(_) => Self::Healthy,
        }
    }

    fn color(self) -> Color {
        match self {
            Self::Healthy => Color::from_rgba8(0x2E, 0xCC, 0x71, 0xFF),
            Self::Warning => Color::from_rgba8(0xF1, 0xC4, 0x0F, 0xFF),
            Self::Critical => Color::from_rgba8(0xE7, 0x4C, 0x3C, 0xFF),
            Self::Unknown => Color::from_rgba8(0x95, 0xA5, 0xA6, 0xFF),
        }
    }
}

pub struct TrayIconBitmap {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

pub fn render_tray_icon(percent: Option<u8>) -> TrayIconBitmap {
    let size = TRAY_SIZE;
    let mut pixmap = Pixmap::new(size, size).expect("alloc pixmap");
    pixmap.fill(Color::TRANSPARENT);

    let tier = HealthTier::from_percent(percent);
    let color = tier.color();

    draw_spark(&mut pixmap, color);
    draw_status_dot(&mut pixmap, color);

    TrayIconBitmap {
        width: size,
        height: size,
        rgba: pixmap.take(),
    }
}

fn draw_spark(pixmap: &mut Pixmap, color: Color) {
    let s = pixmap.width() as f32;
    let cx = s * 0.42;
    let cy = s * 0.5;
    let outer = s * 0.30;
    let inner = s * 0.12;

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

fn draw_status_dot(pixmap: &mut Pixmap, color: Color) {
    let s = pixmap.width() as f32;
    let cx = s * 0.80;
    let cy = s * 0.78;
    let r = s * 0.16;

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
        assert_eq!(HealthTier::from_percent(Some(89)), HealthTier::Warning);
        assert_eq!(HealthTier::from_percent(Some(90)), HealthTier::Critical);
    }

    #[test]
    fn renders_nonempty_bitmap() {
        let bmp = render_tray_icon(Some(42));
        assert_eq!(bmp.width, TRAY_SIZE);
        assert_eq!(bmp.rgba.len(), (TRAY_SIZE * TRAY_SIZE * 4) as usize);
        assert!(bmp.rgba.iter().any(|&b| b != 0));
    }
}
