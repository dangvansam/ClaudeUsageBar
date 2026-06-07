use anyhow::{Context, Result};
use serde::Deserialize;
use std::time::Duration;

const STATUS_URL: &str = "https://status.claude.com/api/v2/summary.json";

#[derive(Clone, Debug)]
pub enum StatusIndicator {
    None,
    Minor,
    Major,
    Critical,
    Maintenance,
    Unknown(#[allow(dead_code)] String),
}

impl StatusIndicator {
    pub fn label(&self) -> &'static str {
        match self {
            Self::None => "All Systems Operational",
            Self::Minor => "Minor Outage",
            Self::Major => "Major Outage",
            Self::Critical => "Critical Outage",
            Self::Maintenance => "Maintenance",
            Self::Unknown(_) => "Unknown",
        }
    }

    pub fn is_healthy(&self) -> bool {
        matches!(self, Self::None)
    }
}

#[derive(Clone, Debug)]
pub struct StatusSummary {
    pub indicator: StatusIndicator,
    pub description: String,
}

pub struct StatusClient {
    agent: ureq::Agent,
}

impl Default for StatusClient {
    fn default() -> Self {
        Self::new()
    }
}

impl StatusClient {
    pub fn new() -> Self {
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(10))
            .timeout_read(Duration::from_secs(15))
            .build();
        Self { agent }
    }

    pub fn fetch(&self) -> Result<StatusSummary> {
        let resp = self.agent.get(STATUS_URL).call().context("status fetch failed")?;
        let raw: RawSummary = resp.into_json().context("decoding status JSON")?;
        let indicator = match raw.status.indicator.as_str() {
            "none" => StatusIndicator::None,
            "minor" => StatusIndicator::Minor,
            "major" => StatusIndicator::Major,
            "critical" => StatusIndicator::Critical,
            "maintenance" => StatusIndicator::Maintenance,
            other => StatusIndicator::Unknown(other.to_string()),
        };
        Ok(StatusSummary {
            indicator,
            description: raw.status.description,
        })
    }
}

#[derive(Deserialize)]
struct RawSummary {
    status: RawStatus,
}

#[derive(Deserialize)]
struct RawStatus {
    indicator: String,
    description: String,
}
