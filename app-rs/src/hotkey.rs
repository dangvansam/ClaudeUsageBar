use anyhow::{Context, Result};
use global_hotkey::hotkey::{Code, HotKey, Modifiers};
use global_hotkey::{GlobalHotKeyManager, HotKeyState};

pub struct HotkeyController {
    manager: GlobalHotKeyManager,
    hotkey: Option<HotKey>,
}

impl HotkeyController {
    pub fn new() -> Result<Self> {
        let manager = GlobalHotKeyManager::new().context("init global hotkey manager")?;
        Ok(Self { manager, hotkey: None })
    }

    pub fn set_enabled(&mut self, enabled: bool) -> Result<()> {
        if enabled && self.hotkey.is_none() {
            let modifier = if cfg!(target_os = "macos") {
                Modifiers::META
            } else {
                Modifiers::CONTROL
            };
            let hk = HotKey::new(Some(modifier), Code::KeyU);
            self.manager.register(hk).context("register Ctrl/Cmd+U")?;
            self.hotkey = Some(hk);
        } else if !enabled {
            if let Some(hk) = self.hotkey.take() {
                let _ = self.manager.unregister(hk);
            }
        }
        Ok(())
    }

    pub fn matches(&self, id: u32, state: HotKeyState) -> bool {
        state == HotKeyState::Pressed && self.hotkey.map(|h| h.id() == id).unwrap_or(false)
    }
}
