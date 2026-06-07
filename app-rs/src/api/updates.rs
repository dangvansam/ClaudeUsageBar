use anyhow::{Context, Result};
use serde::Deserialize;
use std::time::Duration;

const LATEST_URL: &str =
    "https://raw.githubusercontent.com/Artzainnn/ClaudeUsageBar/main/website/latest-v1.json";

#[derive(Clone, Debug, Deserialize)]
#[allow(dead_code)]
pub struct UpdateButton {
    pub label: String,
    pub url: String,
    #[serde(default)]
    pub style: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[allow(dead_code)]
pub struct UpdateInfo {
    pub version: String,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub buttons: Vec<UpdateButton>,
}

impl UpdateInfo {
    pub fn is_newer_than(&self, current: &str) -> bool {
        compare_semver(&self.version, current).is_gt()
    }

    pub fn download_url(&self) -> Option<&str> {
        self.buttons.first().map(|b| b.url.as_str())
    }
}

pub struct UpdateClient {
    agent: ureq::Agent,
}

impl Default for UpdateClient {
    fn default() -> Self {
        Self::new()
    }
}

impl UpdateClient {
    pub fn new() -> Self {
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(10))
            .timeout_read(Duration::from_secs(15))
            .build();
        Self { agent }
    }

    pub fn fetch(&self) -> Result<UpdateInfo> {
        let resp = self.agent.get(LATEST_URL).call().context("update fetch failed")?;
        let info: UpdateInfo = resp.into_json().context("decoding update JSON")?;
        Ok(info)
    }
}

fn compare_semver(a: &str, b: &str) -> std::cmp::Ordering {
    use std::cmp::Ordering;
    let to_parts = |s: &str| -> Vec<u32> {
        s.trim_start_matches('v')
            .split('.')
            .map(|p| p.chars().take_while(|c| c.is_ascii_digit()).collect::<String>())
            .map(|p| p.parse::<u32>().unwrap_or(0))
            .collect()
    };
    let ap = to_parts(a);
    let bp = to_parts(b);
    for i in 0..ap.len().max(bp.len()) {
        let av = ap.get(i).copied().unwrap_or(0);
        let bv = bp.get(i).copied().unwrap_or(0);
        match av.cmp(&bv) {
            Ordering::Equal => continue,
            ord => return ord,
        }
    }
    Ordering::Equal
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cmp::Ordering;

    #[test]
    fn semver_compare_basic() {
        assert_eq!(compare_semver("1.2.3", "1.2.3"), Ordering::Equal);
        assert_eq!(compare_semver("1.2.4", "1.2.3"), Ordering::Greater);
        assert_eq!(compare_semver("1.2.0", "1.2.3"), Ordering::Less);
        assert_eq!(compare_semver("2.0.0", "1.99.99"), Ordering::Greater);
        assert_eq!(compare_semver("v1.2.3", "1.2.3"), Ordering::Equal);
    }
}
