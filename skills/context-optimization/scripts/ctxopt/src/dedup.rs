//! `ctxopt dedup` — near-duplicate block detector via SHA-256 chunks.
//! Equivalent to legacy 02-dedup-detect.sh.

use crate::emit::{log_finding, FindingWriter};
use crate::finding::{Category, Finding, Severity};
use anyhow::{Context, Result};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::path::Path;
use walkdir::{DirEntry, WalkDir};

const TARGET_EXTENSIONS: &[&str] = &["md", "txt"];
const EXCLUDED_PARTS: &[&str] = &[".git", "node_modules", ".venv", "__pycache__", "out", "target"];

fn is_excluded(entry: &DirEntry) -> bool {
    entry
        .path()
        .components()
        .any(|c| EXCLUDED_PARTS.iter().any(|ex| c.as_os_str() == *ex))
}

fn has_target_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| TARGET_EXTENSIONS.contains(&e))
        .unwrap_or(false)
}

/// Normalize whitespace for fuzzy chunk matching: split on whitespace, rejoin with single space.
fn normalize(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Hash bytes → 16-char hex prefix of SHA-256.
fn hash_prefix(content: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    let digest = hasher.finalize();
    let mut s = String::with_capacity(16);
    for b in digest.iter().take(8) {
        s.push_str(&format!("{:02x}", b));
    }
    s
}

pub fn run(
    project_root: &Path,
    chunk_lines: usize,
    min_content_chars: usize,
    writer: &mut dyn FindingWriter,
    quiet: bool,
) -> Result<()> {
    let project_root = project_root
        .canonicalize()
        .with_context(|| format!("project_root not readable: {}", project_root.display()))?;

    if !quiet {
        eprintln!(
            "[INFO]  Scanning {} for duplicate content blocks ({}-line chunks) ...",
            project_root.display(),
            chunk_lines
        );
    }

    // Map<hash_prefix, Vec<location: "path:line">>
    let mut by_hash: HashMap<String, Vec<String>> = HashMap::new();

    for entry in WalkDir::new(&project_root).into_iter().filter_entry(|e| !is_excluded(e)) {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };
        if !entry.file_type().is_file() || !has_target_extension(entry.path()) {
            continue;
        }
        let path = entry.into_path();
        let rel = path
            .strip_prefix(&project_root)
            .unwrap_or(&path)
            .to_string_lossy()
            .to_string();
        let text = match std::fs::read_to_string(&path) {
            Ok(t) => t,
            Err(_) => continue,
        };
        let lines: Vec<&str> = text.lines().collect();
        let mut start = 0;
        while start < lines.len() {
            let end = (start + chunk_lines).min(lines.len());
            let chunk = lines[start..end].join("\n");
            let normalized = normalize(&chunk);
            if normalized.len() >= min_content_chars {
                let h = hash_prefix(&normalized);
                let location = format!("{rel}:{}", start + 1);
                by_hash.entry(h).or_default().push(location);
            }
            start += chunk_lines;
        }
    }

    let mut duplicate_groups: Vec<(String, Vec<String>)> = by_hash
        .into_iter()
        .filter(|(_, locs)| locs.len() >= 2)
        .collect();
    duplicate_groups.sort_by(|a, b| b.1.len().cmp(&a.1.len()));

    let total_dup_chunks: usize = duplicate_groups.iter().map(|(_, l)| l.len()).sum();

    for (rank, (h, locs)) in duplicate_groups.iter().take(20).enumerate() {
        let rank = rank + 1;
        let copies = locs.len();

        let severity = if copies >= 5 {
            Severity::High
        } else if copies >= 3 {
            Severity::Medium
        } else {
            Severity::Low
        };

        let impact = format!(
            "Same {chunk_lines}-line block appears {copies} times across files. Estimated wasted tokens: ~{} ({chunk_lines} lines × ~10 tokens/line × {} extra copies).",
            (copies - 1) * chunk_lines * 10,
            copies - 1
        );
        let remediation = "Apply §10 dedup before LLM call. Keep canonical version; replace duplicates with references. Particularly relevant in RAG pipelines and codebases with repeated headers.".to_string();

        let evidence = json!({
            "hash_prefix": h,
            "copies": copies,
            "locations": locs.iter().take(10).cloned().collect::<Vec<_>>(),
            "chunk_size_lines": chunk_lines,
        });

        let finding = Finding::new(
            format!("DUP-{rank:03}"),
            "dedup",
            severity,
            Category::Bloat,
            locs[0].clone(),
            impact,
            remediation,
            evidence,
        );
        log_finding(&finding, quiet);
        writer.write(&finding)?;
    }

    let summary = Finding::new(
        "DUP-SUM",
        "dedup",
        Severity::Info,
        Category::Bloat,
        project_root.to_string_lossy(),
        format!(
            "Detected {} duplicate-chunk group(s) across the corpus.",
            duplicate_groups.len()
        ),
        "Use as evidence to prioritize §10 dedup in the optimization plan.",
        json!({
            "duplicate_groups": duplicate_groups.len(),
            "total_duplicate_chunks": total_dup_chunks,
        }),
    );
    log_finding(&summary, quiet);
    writer.write(&summary)?;

    if !quiet {
        eprintln!(
            "[OK]    Dedup detection complete. {} group(s) found.",
            duplicate_groups.len()
        );
    }
    Ok(())
}
