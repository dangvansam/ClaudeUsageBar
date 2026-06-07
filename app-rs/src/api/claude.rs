use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use std::time::Duration;

const USER_AGENT: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

#[derive(Clone, Debug, Default)]
pub struct UsageWindow {
    pub utilization: u8,
    pub resets_at: Option<DateTime<Utc>>,
}

#[derive(Clone, Debug, Default)]
pub struct UsageSnapshot {
    pub session: UsageWindow,
    pub weekly: UsageWindow,
    pub weekly_sonnet: Option<UsageWindow>,
    pub fetched_at: Option<DateTime<Utc>>,
}

impl UsageSnapshot {
    pub fn session_percent(&self) -> u8 {
        self.session.utilization.min(100)
    }
}

pub struct ClaudeClient {
    agent: ureq::Agent,
}

impl Default for ClaudeClient {
    fn default() -> Self {
        Self::new()
    }
}

impl ClaudeClient {
    pub fn new() -> Self {
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(10))
            .timeout_read(Duration::from_secs(15))
            .timeout_write(Duration::from_secs(15))
            .user_agent(USER_AGENT)
            .build();
        Self { agent }
    }

    pub fn fetch_usage(&self, cookie: &str) -> Result<UsageSnapshot> {
        let cookie = cookie.trim();
        if cookie.is_empty() {
            return Err(anyhow!("Session cookie not set"));
        }
        let org_id = self.resolve_org_id(cookie)?;
        self.fetch_usage_for_org(cookie, &org_id)
    }

    fn resolve_org_id(&self, cookie: &str) -> Result<String> {
        if let Some(id) = extract_last_active_org(cookie) {
            return Ok(id);
        }
        let session_key = extract_session_key(cookie).unwrap_or(cookie.to_string());
        let resp = self
            .agent
            .get("https://claude.ai/api/bootstrap")
            .set("Cookie", &format!("sessionKey={}", session_key))
            .set("Accept", "application/json")
            .call()
            .context("bootstrap request failed")?;
        let body: BootstrapResponse = resp.into_json().context("decoding bootstrap JSON")?;
        body.account
            .and_then(|a| a.last_active_org_id)
            .ok_or_else(|| anyhow!("Could not extract org id from bootstrap"))
    }

    fn fetch_usage_for_org(&self, cookie: &str, org_id: &str) -> Result<UsageSnapshot> {
        let url = format!("https://claude.ai/api/organizations/{}/usage", org_id);
        let resp = self
            .agent
            .get(&url)
            .set("Cookie", cookie)
            .set("Accept", "*/*")
            .set("Content-Type", "application/json")
            .set("Origin", "https://claude.ai")
            .set("Referer", "https://claude.ai")
            .set("authority", "claude.ai")
            .call();

        let resp = match resp {
            Ok(r) => r,
            Err(ureq::Error::Status(code, _)) => {
                return Err(anyhow!("HTTP {}", code));
            }
            Err(e) => return Err(anyhow!("network error: {}", e)),
        };

        let raw: RawUsage = resp.into_json().context("decoding usage JSON")?;
        Ok(UsageSnapshot {
            session: raw.five_hour.unwrap_or_default().into(),
            weekly: raw.seven_day.unwrap_or_default().into(),
            weekly_sonnet: raw.seven_day_sonnet.map(Into::into),
            fetched_at: Some(Utc::now()),
        })
    }
}

fn extract_last_active_org(cookie: &str) -> Option<String> {
    for part in cookie.split(';') {
        let trimmed = part.trim();
        if let Some(rest) = trimmed.strip_prefix("lastActiveOrg=") {
            return Some(rest.to_string());
        }
    }
    None
}

fn extract_session_key(cookie: &str) -> Option<String> {
    for part in cookie.split(';') {
        let trimmed = part.trim();
        if let Some(rest) = trimmed.strip_prefix("sessionKey=") {
            return Some(rest.to_string());
        }
    }
    None
}

#[derive(Deserialize)]
struct BootstrapResponse {
    account: Option<BootstrapAccount>,
}

#[derive(Deserialize)]
struct BootstrapAccount {
    #[serde(rename = "lastActiveOrgId")]
    last_active_org_id: Option<String>,
}

#[derive(Deserialize, Default)]
struct RawWindow {
    #[serde(default)]
    utilization: f64,
    #[serde(default)]
    resets_at: Option<String>,
}

impl From<RawWindow> for UsageWindow {
    fn from(raw: RawWindow) -> Self {
        let utilization = raw.utilization.round().clamp(0.0, 100.0) as u8;
        let resets_at = raw
            .resets_at
            .and_then(|s| DateTime::parse_from_rfc3339(&s).ok())
            .map(|d| d.with_timezone(&Utc));
        UsageWindow { utilization, resets_at }
    }
}

#[derive(Deserialize)]
struct RawUsage {
    #[serde(default)]
    five_hour: Option<RawWindow>,
    #[serde(default)]
    seven_day: Option<RawWindow>,
    #[serde(default)]
    seven_day_sonnet: Option<RawWindow>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_last_active_org_from_cookie() {
        let cookie = "foo=1; lastActiveOrg=abc-123; bar=2";
        assert_eq!(extract_last_active_org(cookie).as_deref(), Some("abc-123"));
    }

    #[test]
    fn extracts_session_key_from_cookie() {
        let cookie = "sessionKey=secret; lastActiveOrg=org";
        assert_eq!(extract_session_key(cookie).as_deref(), Some("secret"));
    }

    #[test]
    fn raw_window_clamps_utilization() {
        let raw = RawWindow { utilization: 137.6, resets_at: None };
        let w: UsageWindow = raw.into();
        assert_eq!(w.utilization, 100);
    }

    #[test]
    fn raw_window_parses_iso8601() {
        let raw = RawWindow {
            utilization: 42.0,
            resets_at: Some("2026-06-05T12:34:56.000Z".into()),
        };
        let w: UsageWindow = raw.into();
        assert_eq!(w.utilization, 42);
        assert!(w.resets_at.is_some());
    }
}
