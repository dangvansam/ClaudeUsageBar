use std::process::Command;

pub fn startup_checks() {
    if is_gnome() && !has_appindicator_extension() {
        log::warn!(
            "Running under GNOME without an AppIndicator extension. \
             Install https://extensions.gnome.org/extension/615/appindicator-support/ \
             so the tray icon is visible."
        );
        let _ = notify_rust::Notification::new()
            .summary("ClaudeUsageBar tray needs GNOME extension")
            .body(
                "GNOME hides system tray icons by default. Install the \
                 AppIndicator extension to see the Claude usage icon.",
            )
            .icon("claude-usage-bar")
            .appname("ClaudeUsageBar")
            .show();
    }
}

fn is_gnome() -> bool {
    let desktop =
        std::env::var("XDG_CURRENT_DESKTOP").unwrap_or_default().to_ascii_lowercase();
    desktop.contains("gnome") || desktop.contains("unity")
}

fn has_appindicator_extension() -> bool {
    let Ok(out) =
        Command::new("gnome-extensions").args(["list", "--enabled"]).output()
    else {
        return true;
    };
    if !out.status.success() {
        return true;
    }
    let stdout = String::from_utf8_lossy(&out.stdout);
    stdout.lines().any(|l| {
        let l = l.trim().to_ascii_lowercase();
        l.contains("appindicator") || l.contains("ubuntu-appindicators")
    })
}
