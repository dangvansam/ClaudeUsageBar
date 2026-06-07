pub fn startup_checks() {
    register_aumid();
}

#[cfg(target_os = "windows")]
fn register_aumid() {
    use windows::core::HSTRING;
    use windows::Win32::UI::Shell::SetCurrentProcessExplicitAppUserModelID;
    let aumid = HSTRING::from("com.claude.usagebar");
    unsafe {
        let _ = SetCurrentProcessExplicitAppUserModelID(&aumid);
    }
}

#[cfg(not(target_os = "windows"))]
fn register_aumid() {}
