mod cli;
mod count;
mod dedup;
mod emit;
mod finding;
mod report;
mod scan;
mod toon;

use anyhow::Result;
use clap::Parser;
use cli::{Cli, Command, CommonOpts};
use std::path::Path;

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Scan {
            project_root,
            common,
            thresholds,
        } => {
            init_out_dir(&common)?;
            backup_existing_findings(&common)?;
            let mut writer = emit::open_findings_writer(&common.out_dir, common.format)?;
            scan::run(&project_root, &thresholds, &mut *writer, common.quiet)?;
            writer.finalize()?;
        }
        Command::Count {
            project_root,
            common,
            thresholds,
            encoding,
        } => {
            init_out_dir(&common)?;
            backup_existing_findings(&common)?;
            let mut writer = emit::open_findings_writer(&common.out_dir, common.format)?;
            count::run(&project_root, &thresholds, encoding, &mut *writer, common.quiet)?;
            writer.finalize()?;
        }
        Command::Dedup {
            project_root,
            common,
            chunk_lines,
            min_content_chars,
        } => {
            init_out_dir(&common)?;
            backup_existing_findings(&common)?;
            let mut writer = emit::open_findings_writer(&common.out_dir, common.format)?;
            dedup::run(
                &project_root,
                chunk_lines,
                min_content_chars,
                &mut *writer,
                common.quiet,
            )?;
            writer.finalize()?;
        }
        Command::RunAll {
            project_root,
            common,
        } => run_all(&project_root, &common)?,
        Command::Report {
            findings_path,
            format,
        } => report::run(&findings_path, format)?,
    }
    Ok(())
}

fn init_out_dir(common: &CommonOpts) -> Result<()> {
    std::fs::create_dir_all(&common.out_dir)?;
    Ok(())
}

/// Back up any existing `findings.{toon,jsonl,json}` so a fresh run starts clean.
fn backup_existing_findings(common: &CommonOpts) -> Result<()> {
    for name in ["findings.toon", "findings.jsonl", "findings.json"] {
        let path = common.out_dir.join(name);
        if path.exists() && std::fs::metadata(&path).map(|m| m.len() > 0).unwrap_or(false) {
            let stamp = chrono::Utc::now().format("%Y%m%d-%H%M%S").to_string();
            let stem = Path::new(name).file_stem().unwrap().to_string_lossy();
            let ext = Path::new(name).extension().unwrap().to_string_lossy();
            let backup = common.out_dir.join(format!("{stem}.{stamp}.{ext}"));
            let _ = std::fs::rename(&path, &backup);
            if !common.quiet {
                eprintln!(
                    "[INFO]  Previous {} backed up to {}",
                    name,
                    backup.display()
                );
            }
        }
    }
    Ok(())
}

fn run_all(project_root: &Path, common: &CommonOpts) -> Result<()> {
    init_out_dir(common)?;
    backup_existing_findings(common)?;

    if !common.quiet {
        eprintln!("[INFO]  ============================================================");
        eprintln!("[INFO]  Running scan + count + dedup");
        eprintln!("[INFO]  ============================================================");
    }

    // Single writer accumulates all phases' findings.
    let mut writer = emit::open_findings_writer(&common.out_dir, common.format)?;

    let scan_thresholds = cli::SizeThresholds {
        threshold_high: 40 * 1024,
        threshold_medium: 20 * 1024,
        threshold_low: 8 * 1024,
    };
    let count_thresholds = cli::TokenThresholds {
        threshold_high_tokens: 10_000,
        threshold_medium_tokens: 5_000,
        threshold_low_tokens: 2_000,
    };

    if let Err(e) = scan::run(project_root, &scan_thresholds, &mut *writer, common.quiet) {
        eprintln!("[WARN]  scan exited non-zero (continuing): {e:#}");
    }
    if let Err(e) = count::run(
        project_root,
        &count_thresholds,
        cli::Encoding::Cl100kBase,
        &mut *writer,
        common.quiet,
    ) {
        eprintln!("[WARN]  count exited non-zero (continuing): {e:#}");
    }
    if let Err(e) = dedup::run(project_root, 50, 50, &mut *writer, common.quiet) {
        eprintln!("[WARN]  dedup exited non-zero (continuing): {e:#}");
    }
    writer.finalize()?;

    // Aggregate: re-load from the file we just wrote, then emit report.md + summary.{json,toon}.
    let findings_filename = match common.format {
        cli::Format::Toon => "findings.toon",
        cli::Format::Jsonl => "findings.jsonl",
        cli::Format::Json => "findings.json",
    };
    let _ = findings_filename;

    // For aggregation we always need a parseable form (jsonl or json). If user picked TOON, we
    // rebuild from in-memory by re-reading the directory's findings.{jsonl,json} fallback. To
    // keep it simple and robust, write a sidecar findings.jsonl alongside TOON output for the
    // aggregator's consumption.
    if common.format == cli::Format::Toon {
        let sidecar = common.out_dir.join("findings.jsonl");
        let mut sidecar_writer = emit::JsonlWriter::create(&sidecar)?;
        // Re-dump from the TOON buffer is not trivial; instead, the simplest path is to
        // re-run the three phases again with a JSONL writer. We avoid that double cost by
        // reading our own TOON file's `findings[N]{...}:` block back through a tiny parser.
        // Implementation kept minimal: we don't re-parse; we simply rerun a JSONL-only emit
        // pass. For typical fixtures this is fast (< 100ms) and keeps logic auditable.
        if let Err(e) = scan::run(
            project_root,
            &scan_thresholds,
            &mut sidecar_writer,
            true, // suppress duplicate logs
        ) {
            eprintln!("[WARN]  scan (sidecar) failed: {e:#}");
        }
        if let Err(e) = count::run(
            project_root,
            &count_thresholds,
            cli::Encoding::Cl100kBase,
            &mut sidecar_writer,
            true,
        ) {
            eprintln!("[WARN]  count (sidecar) failed: {e:#}");
        }
        if let Err(e) = dedup::run(project_root, 50, 50, &mut sidecar_writer, true) {
            eprintln!("[WARN]  dedup (sidecar) failed: {e:#}");
        }
        emit::FindingWriter::finalize(&mut sidecar_writer)?;
    }

    if !common.quiet {
        eprintln!("[INFO]  ============================================================");
        eprintln!("[INFO]  Aggregating findings...");
        eprintln!("[INFO]  ============================================================");
    }

    let parseable = if common.format == cli::Format::Json {
        common.out_dir.join("findings.json")
    } else {
        common.out_dir.join("findings.jsonl")
    };
    let findings = report::load_findings(&parseable)?;
    report::write_report_files(&common.out_dir, &findings)?;

    if !common.quiet {
        eprintln!(
            "[OK]    Run complete. {} finding(s) recorded.",
            findings.len()
        );
        eprintln!("        Markdown report: {}", common.out_dir.join("report.md").display());
        eprintln!("        JSON summary:    {}", common.out_dir.join("summary.json").display());
        eprintln!("        TOON summary:    {}", common.out_dir.join("summary.toon").display());
        eprintln!("        Raw findings:    {}", parseable.display());
    }
    Ok(())
}
