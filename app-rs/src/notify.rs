use notify_rust::Notification;

const THRESHOLDS: [u8; 4] = [25, 50, 75, 90];
#[allow(dead_code)]
const APP_ID: &str = "com.claude.usagebar";

pub struct Notifier;

impl Notifier {
    pub fn maybe_notify_threshold(percent: u8, last_notified: u8) -> Option<u8> {
        let next = THRESHOLDS
            .iter()
            .copied()
            .filter(|&t| percent >= t && last_notified < t)
            .max()?;
        Self::send(
            "Claude Usage Alert",
            &format!("You've hit {}% of your 5-hour session limit.", percent),
        );
        Some(next)
    }

    pub fn reset_threshold_if_dropped(percent: u8, last_notified: u8) -> u8 {
        if percent < last_notified {
            THRESHOLDS.iter().copied().filter(|&t| t <= percent).max().unwrap_or(0)
        } else {
            last_notified
        }
    }

    #[allow(dead_code)]
    pub fn send_test() {
        Self::send(
            "Claude Usage Alert",
            "Test notification — you've reached 75% of your 5-hour session limit.",
        );
    }

    pub fn send_status(label: &str, description: &str) {
        Self::send(&format!("Claude status: {}", label), description);
    }

    pub fn send_update_available(version: &str) {
        Self::send(
            "ClaudeUsageBar update available",
            &format!("Version {} is out. Open the popup to install.", version),
        );
    }

    fn send(title: &str, body: &str) {
        let mut n = Notification::new();
        n.summary(title).body(body).appname("ClaudeUsageBar");
        #[cfg(target_os = "windows")]
        {
            n.app_id(APP_ID);
        }
        #[cfg(target_os = "linux")]
        {
            n.icon("claude-usage-bar");
        }
        if let Err(e) = n.show() {
            log::warn!("notification failed: {}", e);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn threshold_state_machine_does_not_double_fire() {
        let last = Notifier::reset_threshold_if_dropped(60, 50);
        assert_eq!(last, 50);
    }

    #[test]
    fn threshold_resets_when_drop() {
        let last = Notifier::reset_threshold_if_dropped(40, 75);
        assert_eq!(last, 25);
    }

    #[test]
    fn threshold_resets_to_zero_when_far_drop() {
        let last = Notifier::reset_threshold_if_dropped(10, 90);
        assert_eq!(last, 0);
    }
}
