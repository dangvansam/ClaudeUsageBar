#[cfg(target_os = "linux")]
pub mod linux;

#[cfg(target_os = "windows")]
pub mod windows;

#[cfg(target_os = "macos")]
pub mod macos;

pub fn after_startup_checks() {
    #[cfg(target_os = "linux")]
    {
        linux::startup_checks();
    }
    #[cfg(target_os = "windows")]
    {
        windows::startup_checks();
    }
}
