use clap::{Parser, Subcommand, ValueEnum};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "ctxopt", version, about = "Context-optimization audit tool", long_about = None)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Scan project root for context-candidate files; emit findings on size offenders.
    Scan {
        project_root: PathBuf,
        #[command(flatten)]
        common: CommonOpts,
        #[command(flatten)]
        thresholds: SizeThresholds,
    },
    /// Count tokens accurately via tiktoken; emit findings on token-budget offenders.
    Count {
        project_root: PathBuf,
        #[command(flatten)]
        common: CommonOpts,
        #[command(flatten)]
        thresholds: TokenThresholds,
        #[arg(long, value_enum, default_value = "cl100k_base")]
        encoding: Encoding,
    },
    /// Detect near-duplicate content blocks via SHA-256 hashing of N-line chunks.
    Dedup {
        project_root: PathBuf,
        #[command(flatten)]
        common: CommonOpts,
        #[arg(long, default_value_t = 50)]
        chunk_lines: usize,
        #[arg(long, default_value_t = 50)]
        min_content_chars: usize,
    },
    /// Run scan + count + dedup in sequence; aggregate via report subcommand.
    RunAll {
        project_root: PathBuf,
        #[command(flatten)]
        common: CommonOpts,
    },
    /// Aggregate a findings file (JSONL/TOON/JSON) into Markdown report + summary.
    Report {
        findings_path: PathBuf,
        #[arg(long, value_enum, default_value = "md")]
        format: ReportFormat,
    },
}

#[derive(clap::Args, Debug, Clone)]
pub struct CommonOpts {
    /// Output directory for findings + reports.
    #[arg(long, default_value = "./out", global = true)]
    pub out_dir: PathBuf,

    /// Output format for findings stream.
    #[arg(long, value_enum, default_value = "toon", global = true)]
    pub format: Format,

    /// Verbose logs to stderr.
    #[arg(long, short = 'v', global = true)]
    pub verbose: bool,

    /// Suppress info-level logs.
    #[arg(long, short = 'q', global = true)]
    pub quiet: bool,
}

#[derive(clap::Args, Debug, Clone)]
pub struct SizeThresholds {
    #[arg(long, default_value_t = 40 * 1024)]
    pub threshold_high: u64,
    #[arg(long, default_value_t = 20 * 1024)]
    pub threshold_medium: u64,
    #[arg(long, default_value_t = 8 * 1024)]
    pub threshold_low: u64,
}

#[derive(clap::Args, Debug, Clone)]
pub struct TokenThresholds {
    #[arg(long, default_value_t = 10_000)]
    pub threshold_high_tokens: usize,
    #[arg(long, default_value_t = 5_000)]
    pub threshold_medium_tokens: usize,
    #[arg(long, default_value_t = 2_000)]
    pub threshold_low_tokens: usize,
}

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum Format {
    Toon,
    Jsonl,
    Json,
}

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReportFormat {
    Md,
    Toon,
    Json,
}

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum Encoding {
    #[value(name = "cl100k_base")]
    Cl100kBase,
    #[value(name = "o200k_base")]
    O200kBase,
}

impl Encoding {
    pub fn name(&self) -> &'static str {
        match self {
            Encoding::Cl100kBase => "cl100k_base",
            Encoding::O200kBase => "o200k_base",
        }
    }
}
