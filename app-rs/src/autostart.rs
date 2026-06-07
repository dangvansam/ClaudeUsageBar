use anyhow::{Context, Result};
use auto_launch::AutoLaunchBuilder;
use std::env;

pub fn set_launch_at_login(enabled: bool) -> Result<()> {
    let exe = env::current_exe().context("current_exe failed")?;
    let exe_str = exe.to_string_lossy().to_string();
    let launcher = AutoLaunchBuilder::new()
        .set_app_name("ClaudeUsageBar")
        .set_app_path(&exe_str)
        .set_use_launch_agent(true)
        .build()
        .context("building auto-launch")?;
    if enabled {
        launcher.enable().context("enable autostart")?;
    } else {
        launcher.disable().context("disable autostart")?;
    }
    Ok(())
}
