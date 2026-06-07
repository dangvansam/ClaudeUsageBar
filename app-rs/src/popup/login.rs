//! Scene 3 — onboarding welcome card shown when the cookie is empty.
//! Matches the prototype's centered hero (logo tile → headline → sub →
//! primary CTA → secure-sign-in footer → 3 progress dots) and folds the
//! existing cookie-paste flow under the CTA, since we don't have OAuth yet.

use eframe::egui::{
    self, Color32, CornerRadius, FontFamily, FontId, Margin, RichText, Sense, Stroke, Ui, Vec2,
};

use crate::state::UiCommand;

use super::theme::Palette;
use super::{draw_brand_dot, open_url, pill_button, read_cookie_field};

pub fn render(
    ui: &mut Ui,
    pal: &Palette,
    avail_w: f32,
    cookie: &mut String,
    cookie_dirty: &mut bool,
    tx: &std::sync::mpsc::Sender<UiCommand>,
) {
    let _ = avail_w;
    egui::ScrollArea::vertical().show(ui, |ui| {
        ui.add_space(28.0);
        ui.vertical_centered(|ui| {
            // Card
            let card_w = 320.0_f32.min(ui.available_width() - 24.0);
            egui::Frame::default()
                .fill(pal.bg_card)
                .stroke(Stroke::new(1.0, pal.border))
                .corner_radius(CornerRadius::same(14))
                .inner_margin(Margin::symmetric(22, 22))
                .show(ui, |ui| {
                    ui.set_width(card_w);

                    // Rounded accent logo tile, 56×56 — same as design.
                    ui.vertical_centered(|ui| {
                        draw_brand_dot(ui, pal.accent, 56.0);
                    });

                    ui.add_space(16.0);
                    ui.vertical_centered(|ui| {
                        ui.label(
                            RichText::new("Welcome to Usage Bar")
                                .color(pal.text_primary)
                                .font(FontId::new(18.0, FontFamily::Proportional))
                                .strong(),
                        );
                    });

                    ui.add_space(6.0);
                    ui.vertical_centered_justified(|ui| {
                        ui.label(
                            RichText::new(
                                "Keep an eye on your Claude session and weekly limits — \
                                 right from the menu bar.",
                            )
                            .color(pal.text_secondary),
                        );
                    });

                    ui.add_space(14.0);

                    // Primary CTA — mirrors prototype's "Continue with Claude". Until
                    // OAuth lands, it just opens claude.ai in the browser so the
                    // user can grab their cookie.
                    if pill_button(ui, pal, "✦  Continue with Claude", true).clicked() {
                        open_url("https://claude.ai");
                    }

                    ui.add_space(8.0);
                    ui.vertical_centered(|ui| {
                        ui.label(
                            RichText::new(
                                "We open your browser to sign in securely. \
                                 Usage Bar never sees your password.",
                            )
                            .color(pal.text_muted)
                            .small(),
                        );
                    });

                    ui.add_space(18.0);
                    cookie_panel(ui, pal, cookie, cookie_dirty, tx);

                    ui.add_space(12.0);
                    progress_dots(ui, pal);
                });
        });
        ui.add_space(28.0);
    });
}

fn cookie_panel(
    ui: &mut Ui,
    pal: &Palette,
    cookie: &mut String,
    cookie_dirty: &mut bool,
    tx: &std::sync::mpsc::Sender<UiCommand>,
) {
    egui::Frame::default()
        .fill(pal.bg_inset)
        .stroke(Stroke::new(1.0, pal.border))
        .corner_radius(CornerRadius::same(10))
        .inner_margin(Margin::same(12))
        .show(ui, |ui| {
            ui.label(
                RichText::new("Paste your Claude.ai cookie")
                    .color(pal.text_primary)
                    .strong(),
            );
            ui.add_space(4.0);
            ui.label(
                RichText::new(
                    "DevTools (F12) → Network → any /api/organizations/* request → \
                     copy the entire Cookie header.",
                )
                .color(pal.text_muted)
                .small(),
            );
            ui.add_space(8.0);
            read_cookie_field(
                ui,
                pal,
                cookie,
                cookie_dirty,
                3,
                "Paste full Cookie header here…",
            );
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                let enabled = !cookie.trim().is_empty() && *cookie_dirty;
                let btn = ui.add_enabled(
                    enabled,
                    egui::Button::new(
                        RichText::new("Save & fetch")
                            .color(pal.on_accent)
                            .strong(),
                    )
                    .fill(pal.accent)
                    .corner_radius(CornerRadius::same(8))
                    .min_size(Vec2::new(0.0, 28.0)),
                );
                if btn.clicked() {
                    let _ = tx.send(UiCommand::SaveCookie(cookie.trim().to_string()));
                    *cookie_dirty = false;
                }
            });
        });
}

fn progress_dots(ui: &mut Ui, pal: &Palette) {
    ui.vertical_centered(|ui| {
        let dot = 6.0;
        let active_w = 20.0;
        let total_w = active_w + dot + dot + 12.0; // 2 gaps between 3 items
        let (rect, _) = ui.allocate_exact_size(Vec2::new(total_w, dot), Sense::hover());
        let painter = ui.painter();
        // Active pill (step 1).
        painter.rect_filled(
            egui::Rect::from_min_size(rect.left_top(), Vec2::new(active_w, dot)),
            CornerRadius::same(3),
            pal.accent,
        );
        let mut x = rect.left() + active_w + 6.0;
        for _ in 0..2 {
            painter.circle_filled(
                egui::pos2(x + dot / 2.0, rect.center().y),
                dot / 2.0,
                pal.border_strong,
            );
            x += dot + 6.0;
        }
        let _ = Color32::WHITE;
    });
}
