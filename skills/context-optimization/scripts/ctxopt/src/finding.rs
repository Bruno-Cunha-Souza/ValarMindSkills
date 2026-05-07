use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fmt;

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Critical,
    High,
    Medium,
    Low,
    Info,
}

impl Severity {
    pub fn as_str(&self) -> &'static str {
        match self {
            Severity::Critical => "critical",
            Severity::High => "high",
            Severity::Medium => "medium",
            Severity::Low => "low",
            Severity::Info => "info",
        }
    }
}

impl fmt::Display for Severity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum Category {
    Cost,
    Cache,
    Quality,
    Bloat,
    Architecture,
}

impl Category {
    pub fn as_str(&self) -> &'static str {
        match self {
            Category::Cost => "cost",
            Category::Cache => "cache",
            Category::Quality => "quality",
            Category::Bloat => "bloat",
            Category::Architecture => "architecture",
        }
    }
}

impl fmt::Display for Category {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Finding {
    pub id: String,
    pub phase: String,
    pub severity: Severity,
    pub category: Category,
    pub target: String,
    pub evidence: serde_json::Value,
    pub impact: String,
    pub remediation: String,
    pub timestamp: String,
}

impl Finding {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        id: impl Into<String>,
        phase: impl Into<String>,
        severity: Severity,
        category: Category,
        target: impl Into<String>,
        impact: impl Into<String>,
        remediation: impl Into<String>,
        evidence: serde_json::Value,
    ) -> Self {
        Self {
            id: id.into(),
            phase: phase.into(),
            severity,
            category,
            target: target.into(),
            evidence,
            impact: impact.into(),
            remediation: remediation.into(),
            timestamp: Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        }
    }
}
