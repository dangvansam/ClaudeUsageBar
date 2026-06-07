# claude-usage-bar (Linux + Windows)

Lightweight Rust port of [ClaudeUsageBar](../README.md) for Linux and Windows.
The macOS Swift app under [`../app/`](../app) is unchanged.

## Goals

- **Tiny** — 7.4 MB stripped binary (Linux), single static executable
- **Cold start under 200 ms** — native rendering, no webview
- **RSS ≤ 50 MB** at idle — no Electron, no Chromium
- **1-click install** — `.deb`, `.AppImage`, and Windows `.msi`

## Features (parity with macOS)

- System tray icon, color-coded by 5-hour session usage (green / yellow / red)
- Popup window with progress bars for 5h, 7d, and 7d Sonnet windows
- Anthropic status indicator (status.claude.com)
- Threshold notifications at 25 / 50 / 75 / 90 %
- Global hotkey (Ctrl+U) to toggle the popup
- Auto-launch at login
- Update check against `website/latest-v1.json`

## Install

### Ubuntu / Debian

```sh
sudo apt install ./claude-usage-bar_1.2.1-1_amd64.deb
```

GNOME users also need the [AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/) for tray icons to appear.

### Any Linux (AppImage)

```sh
chmod +x ClaudeUsageBar-x86_64.AppImage
./ClaudeUsageBar-x86_64.AppImage
```

### Windows

Double-click `ClaudeUsageBar-1.2.1-x64.msi`. Installs per-user, no admin prompt.

## Build from source

### Linux

```sh
sudo apt install -y build-essential pkg-config \
    libgtk-3-dev libayatana-appindicator3-dev libxdo-dev \
    libdbus-1-dev libssl-dev libsecret-1-dev

cd app-rs
cargo build --release
./target/release/claude-usage-bar
```

Build `.deb`:

```sh
cargo install cargo-deb
cargo deb --no-build
```

Build AppImage:

```sh
bash ../packaging/linux/appimage/build.sh
```

### Windows

```powershell
cd app-rs
cargo build --release
.\target\release\claude-usage-bar.exe
```

Build MSI (needs `wix` 6 dotnet tool):

```powershell
pwsh -ExecutionPolicy Bypass -File ..\packaging\windows\wix\build.ps1
```

## Architecture

```
src/
  main.rs       entry; spawns worker thread + tray thread; runs eframe
  state.rs      shared AppState + UiCommand enum
  api/
    claude.rs   port of UsageManager (cookie -> org -> /usage)
    status.rs   status.claude.com summary
    updates.rs  latest-v1.json poll + semver compare
  tray.rs       tray-icon menu + dynamic icon updates
  icon.rs       tiny-skia rendering of spark + status dot
  popup.rs      egui UI (onboarding, usage, settings)
  notify.rs     threshold dedupe + notify-rust send
  hotkey.rs     global-hotkey Ctrl+U registration
  storage.rs    keyring (cookie) + JSON config (settings)
  autostart.rs  auto-launch toggle (XDG / registry)
  platform/
    linux.rs    GNOME extension detection + warning
    windows.rs  AUMID registration for WinRT toasts
```

Worker thread polls usage every 5 minutes, status every 10 minutes, updates every hour.
UI thread runs eframe + tray events; communication is `Arc<Mutex<AppState>>` + `mpsc::Sender<UiCommand>`.

## How to get your Claude cookie

1. Open <https://claude.ai> in a browser and sign in.
2. Open DevTools (F12) → Network tab.
3. Click any request to `/api/organizations/...`.
4. In Request Headers, copy the entire `Cookie` value.
5. Paste it into the app's onboarding screen.

The cookie is stored in the OS keyring (Secret Service on Linux, Credential Manager on Windows).

## Verification matrix

- Ubuntu 22.04 GNOME + Wayland
- Ubuntu 24.04 GNOME + X11
- KDE Neon
- Windows 10
- Windows 11

## License

MIT. See [LICENSE](../LICENSE).
