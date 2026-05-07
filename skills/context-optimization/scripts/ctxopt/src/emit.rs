//! FindingWriter trait + implementations for JSONL / TOON / JSON output.

use crate::cli::Format;
use crate::finding::Finding;
use crate::toon;
use std::fs::OpenOptions;
use std::io::{self, BufWriter, Write};
use std::path::Path;

pub trait FindingWriter {
    /// Append a single finding to the output stream.
    fn write(&mut self, f: &Finding) -> io::Result<()>;
    /// Flush + finalize (no-op for JSONL; needed for TOON to flush buffered count).
    fn finalize(&mut self) -> io::Result<()>;
}

/// JSONL: one finding per line.
pub struct JsonlWriter {
    inner: BufWriter<std::fs::File>,
}

impl JsonlWriter {
    pub fn create(path: &Path) -> io::Result<Self> {
        let f = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)?;
        Ok(Self {
            inner: BufWriter::new(f),
        })
    }
}

impl FindingWriter for JsonlWriter {
    fn write(&mut self, f: &Finding) -> io::Result<()> {
        let line = serde_json::to_string(f).map_err(io::Error::other)?;
        self.inner.write_all(line.as_bytes())?;
        self.inner.write_all(b"\n")?;
        Ok(())
    }

    fn finalize(&mut self) -> io::Result<()> {
        self.inner.flush()
    }
}

/// TOON: buffer all findings; emit a single `findings[N]{...}:` block on finalize.
pub struct ToonWriter {
    path: std::path::PathBuf,
    buffer: Vec<Finding>,
}

impl ToonWriter {
    pub fn create(path: &Path) -> io::Result<Self> {
        // Truncate (or create) target file early so a partial run leaves a valid empty file.
        let _ = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(path)?;
        Ok(Self {
            path: path.to_path_buf(),
            buffer: Vec::new(),
        })
    }
}

impl FindingWriter for ToonWriter {
    fn write(&mut self, f: &Finding) -> io::Result<()> {
        self.buffer.push(f.clone());
        Ok(())
    }

    fn finalize(&mut self) -> io::Result<()> {
        let f = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(&self.path)?;
        let mut w = BufWriter::new(f);
        toon::write_findings(&mut w, &self.buffer)?;
        w.flush()
    }
}

/// JSON: buffer all findings; emit a single JSON array.
pub struct JsonWriter {
    path: std::path::PathBuf,
    buffer: Vec<Finding>,
}

impl JsonWriter {
    pub fn create(path: &Path) -> io::Result<Self> {
        let _ = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(path)?;
        Ok(Self {
            path: path.to_path_buf(),
            buffer: Vec::new(),
        })
    }
}

impl FindingWriter for JsonWriter {
    fn write(&mut self, f: &Finding) -> io::Result<()> {
        self.buffer.push(f.clone());
        Ok(())
    }

    fn finalize(&mut self) -> io::Result<()> {
        let f = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(&self.path)?;
        let mut w = BufWriter::new(f);
        serde_json::to_writer_pretty(&mut w, &self.buffer).map_err(io::Error::other)?;
        w.write_all(b"\n")?;
        w.flush()
    }
}

/// Build the appropriate writer based on `--format`. Filename extension is set accordingly.
pub fn open_findings_writer(out_dir: &Path, format: Format) -> io::Result<Box<dyn FindingWriter>> {
    std::fs::create_dir_all(out_dir)?;
    let (filename, writer): (&str, Box<dyn FindingWriter>) = match format {
        Format::Jsonl => ("findings.jsonl", Box::new(JsonlWriter::create(&out_dir.join("findings.jsonl"))?)),
        Format::Toon => ("findings.toon", Box::new(ToonWriter::create(&out_dir.join("findings.toon"))?)),
        Format::Json => ("findings.json", Box::new(JsonWriter::create(&out_dir.join("findings.json"))?)),
    };
    let _ = filename; // referenced for log-side identification if needed
    Ok(writer)
}

/// Log a finding to stderr at the appropriate level given its severity.
pub fn log_finding(f: &Finding, quiet: bool) {
    if quiet {
        return;
    }
    let sev = f.severity.as_str().to_uppercase();
    let prefix = match f.severity {
        crate::finding::Severity::Critical | crate::finding::Severity::High => "[ERR]",
        crate::finding::Severity::Medium | crate::finding::Severity::Low => "[WARN]",
        crate::finding::Severity::Info => "[INFO]",
    };
    eprintln!("{prefix}   [{}] {} — {}", f.id, sev, f.target);
}
