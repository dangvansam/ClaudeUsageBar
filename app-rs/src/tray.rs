use anyhow::{Context, Result};
use tray_icon::menu::{Menu, MenuItem, PredefinedMenuItem};
use tray_icon::{Icon, TrayIcon, TrayIconBuilder};

use crate::icon::{render_tray_icon, TrayIconBitmap};
use crate::storage::{Accent, TrayIconStyle};

pub struct TrayMenuIds {
    pub open: String,
    pub refresh: String,
    pub settings: String,
    pub quit: String,
}

pub struct TrayController {
    pub tray: TrayIcon,
    pub ids: TrayMenuIds,
}

impl TrayController {
    pub fn build() -> Result<Self> {
        let menu = Menu::new();

        let open = MenuItem::new("Open Usage", true, None);
        let refresh = MenuItem::new("Refresh now", true, None);
        let settings = MenuItem::new("Settings…", true, None);
        let quit = MenuItem::new("Quit ClaudeUsageBar", true, None);

        menu.append(&open).ok();
        menu.append(&refresh).ok();
        menu.append(&PredefinedMenuItem::separator()).ok();
        menu.append(&settings).ok();
        menu.append(&PredefinedMenuItem::separator()).ok();
        menu.append(&quit).ok();

        let ids = TrayMenuIds {
            open: open.id().0.clone(),
            refresh: refresh.id().0.clone(),
            settings: settings.id().0.clone(),
            quit: quit.id().0.clone(),
        };

        let icon = build_icon(None, false, TrayIconStyle::Mark, Accent::Warm)?;
        let tray = TrayIconBuilder::new()
            .with_menu(Box::new(menu))
            .with_icon(icon)
            .with_tooltip("Claude Usage Bar")
            .with_title("Claude")
            .build()
            .context("creating tray icon")?;

        Ok(Self { tray, ids })
    }

    pub fn update(
        &self,
        percent: Option<u8>,
        label: &str,
        show_percent: bool,
        style: TrayIconStyle,
        accent: Accent,
    ) {
        if let Ok(icon) = build_icon(percent, show_percent, style, accent) {
            let _ = self.tray.set_icon(Some(icon));
        }
        let _ = self.tray.set_tooltip(Some(label));
        let _ = self.tray.set_title(Some(label));
    }
}

fn build_icon(
    percent: Option<u8>,
    show_percent: bool,
    style: TrayIconStyle,
    accent: Accent,
) -> Result<Icon> {
    let TrayIconBitmap { width, height, rgba } = render_tray_icon(percent, show_percent, style, accent);
    Icon::from_rgba(rgba, width, height).context("Icon::from_rgba")
}
