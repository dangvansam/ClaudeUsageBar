# ClaudeUsageBar

> Track your Claude.ai usage from your menu bar or system tray — **macOS, Linux, and Windows**.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-12.0+-blue.svg)](https://www.apple.com/macos/)
[![Linux](https://img.shields.io/badge/Linux-Ubuntu%2022%2B-orange.svg)](#-download)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-blue.svg)](#-download)

<a href="https://www.producthunt.com/products/claudeusagebar?utm_source=badge-top-post-badge&utm_medium=badge&utm_campaign=badge-claudeusagebar" target="_blank"><img src="https://api.producthunt.com/widgets/embed-image/v1/top-post-badge.svg?post_id=1067826&theme=dark&period=daily&t=1769934818885" alt="ClaudeUsageBar - #1 Product of the Day" width="250" height="54" /></a>

A lightweight, open-source tray application that displays your Claude.ai session and weekly usage limits with real-time updates and notifications. Runs natively on **macOS, Linux, and Windows** — no Electron, no browser, no bloat.

| Platform | Binary | RAM (idle) | Install |
|---|---|---|---|
| macOS    | 1.6 MB universal | ~30 MB | `.dmg` |
| Linux    | 7.4 MB stripped  | ~35 MB | `.deb` / `.AppImage` |
| Windows  | ~8 MB stripped   | ~40 MB | `.msi` (per-user) |

## 📥 Download

**[Download Latest Release →](https://github.com/Artzainnn/ClaudeUsageBar/releases/latest)**

Pick the file for your OS:

- **macOS** — `ClaudeUsageBar-Installer.dmg`
- **Ubuntu / Debian** — `claude-usage-bar_1.2.1-1_amd64.deb`
- **Any Linux** — `ClaudeUsageBar-x86_64.AppImage`
- **Windows 10 / 11** — `ClaudeUsageBar-1.2.1-x64.msi`

### Install in 1 click

<details>
<summary><b>macOS</b></summary>

1. Open the `.dmg`
2. Drag **ClaudeUsageBar** to the Applications folder
3. Launch from Applications
</details>

<details>
<summary><b>Ubuntu / Debian</b></summary>

Double-click the `.deb` file (opens in GNOME Software or KDE Discover), or:

```bash
sudo apt install ./claude-usage-bar_1.2.1-1_amd64.deb
```

**GNOME users:** install the [AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/) so the tray icon is visible (GNOME hides tray icons by default).
</details>

<details>
<summary><b>Any Linux (AppImage)</b></summary>

```bash
chmod +x ClaudeUsageBar-x86_64.AppImage
./ClaudeUsageBar-x86_64.AppImage
```

Portable, no install needed. Works on Arch, Fedora, openSUSE, etc.
</details>

<details>
<summary><b>Windows</b></summary>

1. Double-click `ClaudeUsageBar-1.2.1-x64.msi`
2. Click **Install** (no admin prompt — installs per-user)
3. App launches automatically; icon appears in the system tray

Installer adds a Start Menu shortcut and optional auto-start at login.
</details>

## 📦 Set Up (1 min)

1. Go to [claude.ai/settings/usage](https://claude.ai/settings/usage)
2. Open Developer Tools (`Cmd/Ctrl + Option/Shift + I`) → **Network** tab
3. Refresh the page, click the **"usage"** request
4. Copy the full **"Cookie"** value from the Request Headers
5. Paste it into the app's onboarding screen

![Setup Guide](setup-guide.png)

Your cookie is stored in the **OS keyring** — Keychain (macOS), Secret Service (Linux), Credential Manager (Windows). Never written in plaintext.

## ✨ Features

- 🟢 **Real-time usage tracking** — Monitor session (5-hour) and weekly (7-day) limits
- 🎨 **Color-coded tray icon** — Spark icon changes color: green / yellow / red
- 🔔 **Smart notifications** — Alerts at 25%, 50%, 75%, 90% usage thresholds
- ⌨️ **Global hotkey** — Toggle popup with `Cmd+U` (macOS) or `Ctrl+U` (Linux/Windows)
- ⚡ **Auto-refresh** — Updates every 5 minutes
- 🛰️ **Anthropic status** — Shows status.claude.com state inline
- 🔒 **Privacy-first** — Cookie in OS keyring, no telemetry, no external servers (except claude.ai)
- 📊 **Pro plan support** — Shows weekly Sonnet usage for Pro subscribers
- 🪶 **Lightweight** — Native rendering, no webview, no Electron
- 🚀 **Auto-launch at login** — Optional per platform

[See full feature list →](app/README.md)

## 🚀 Quick Start

1. **Download** the file for your OS from [Releases](https://github.com/Artzainnn/ClaudeUsageBar/releases/latest)
2. **Install** (1 click — see above)
3. **Set cookie** from claude.ai (follow in-app instructions)
4. **Done!** Usage appears in your menu bar / system tray

## 📸 Screenshots

**Menu bar / tray display:**

```
⚡ 45%   (green spark when usage < 70%)
⚡ 78%   (yellow when 70-89%)
⚡ 92%   (red when ≥ 90%)
```

**Popup interface:**
- Session (5-hour) usage with progress bar
- Weekly (7-day) usage with progress bar
- Weekly Sonnet usage (Pro plan only)
- Anthropic status indicator
- Settings for notifications, hotkey, auto-launch

## 📁 Repository Structure

```
app/         macOS menu bar application (Swift / SwiftUI)
app-rs/      Linux + Windows tray application (Rust + egui + tray-icon)
packaging/
  linux/
    debian/  cargo-deb metadata, .desktop file, postinst
    appimage/AppImage build script (AppRun + appimagetool)
  windows/
    wix/     WiX 6 MSI installer definition + build.ps1
website/     Landing page (HTML / CSS)
.github/
  workflows/release.yml — CI builds .deb + .AppImage + .msi on tag push
```

## 🛠️ Build from Source

### macOS (Swift)

```bash
cd app
chmod +x build.sh
./build.sh             # → app/build/ClaudeUsageBar.app
./create_dmg.sh        # → ClaudeUsageBar-Installer.dmg
```

Requires Xcode Command Line Tools and macOS 12+.

### Linux (Rust)

```bash
# System dependencies (Ubuntu / Debian)
sudo apt install -y build-essential pkg-config \
    libgtk-3-dev libayatana-appindicator3-dev libxdo-dev \
    libdbus-1-dev libssl-dev libsecret-1-dev

cd app-rs
cargo build --release
./target/release/claude-usage-bar
```

**Build `.deb`:**
```bash
cargo install cargo-deb
cargo deb --no-build
# → app-rs/target/debian/claude-usage-bar_1.2.1-1_amd64.deb (~2.9 MB)
```

**Build AppImage:**
```bash
bash packaging/linux/appimage/build.sh
# → app-rs/target/appimage/ClaudeUsageBar-x86_64.AppImage
```

### Windows (Rust)

Requires Rust + .NET SDK (for WiX 6 tool).

```powershell
cd app-rs
cargo build --release
.\target\release\claude-usage-bar.exe
```

**Build MSI installer:**
```powershell
pwsh -ExecutionPolicy Bypass -File .\packaging\windows\wix\build.ps1
# → packaging\windows\wix\ClaudeUsageBar-1.2.1-x64.msi
```

[Full Linux/Windows dev guide →](app-rs/README.md)

## 🔧 Architecture

### macOS (`app/`)
- **Swift + SwiftUI + AppKit** — NSStatusBar tray, NSPopover popup
- **Carbon** for global hotkey (`Cmd+U`)
- **NSUserNotification** for system notifications
- Single-file (~1,882 lines), universal binary (arm64 + x86_64), ~1.6 MB

### Linux + Windows (`app-rs/`)
- **Rust + tao + egui** — native rendering, no webview
- **`tray-icon`** — Windows Shell_NotifyIcon, Linux StatusNotifierItem (KDE/Wayland) + XEmbed fallback
- **`global-hotkey`** — Win32 RegisterHotKey, X11/Wayland portal
- **`notify-rust`** — D-Bus on Linux, WinRT toast on Windows
- **`keyring`** — Secret Service (Linux), Credential Manager (Windows)
- **`ureq`** for blocking HTTP (5-min poll, no async runtime needed)
- 7.4 MB stripped binary, ~35 MB RSS at idle

Why not Tauri/Electron? WebView2 + WebKitGTK push idle RAM to 80-120 MB and bundle size > 15 MB. Native rendering keeps the app truly lightweight.

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

- 🐛 Report bugs via [Issues](https://github.com/Artzainnn/ClaudeUsageBar/issues)
- 💡 Suggest features or improvements
- 🔧 Submit pull requests (esp. for tested distros, see [verification matrix](app-rs/README.md#verification-matrix))
- 📖 Improve documentation
- 🌍 Translate the website

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

## ⚠️ Disclaimer

This app uses Claude.ai's internal API endpoints which may change without notice. It is not affiliated with or endorsed by Anthropic. Use at your own risk.

## 🙏 Support

If you find this useful, consider:
- ⭐ Starring this repository
- 📢 Sharing with others who use Claude

## 🔗 Links

- **Website:** [claudeusagebar.com](https://claudeusagebar.com)
- **Issues:** [GitHub Issues](https://github.com/Artzainnn/ClaudeUsageBar/issues)
- **Releases:** [GitHub Releases](https://github.com/Artzainnn/ClaudeUsageBar/releases)

## 🔗 Other projects

- **Mediaboost — Guaranteed PR feature:** [Mediaboost](https://mediaboost.press)
- **CheckWorth — AI net worth estimates from LinkedIn:** [CheckWorth](https://checkworth.app)

---

**Made with ❤️ for the Claude community — on every OS.**
