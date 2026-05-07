//! Smoke tests for ctxopt subcommands. Build + invoke binary against a tiny fixture.

use std::process::Command;

fn ctxopt_bin() -> std::path::PathBuf {
    // Cargo sets CARGO_BIN_EXE_<name> to the test binary path.
    std::path::PathBuf::from(env!("CARGO_BIN_EXE_ctxopt"))
}

#[test]
fn version_prints_on_stdout() {
    let out = Command::new(ctxopt_bin())
        .arg("--version")
        .output()
        .expect("ctxopt --version");
    assert!(out.status.success());
    let s = String::from_utf8_lossy(&out.stdout);
    assert!(s.contains("ctxopt"));
}

#[test]
fn help_lists_all_subcommands() {
    let out = Command::new(ctxopt_bin())
        .arg("--help")
        .output()
        .expect("ctxopt --help");
    assert!(out.status.success());
    let s = String::from_utf8_lossy(&out.stdout);
    for sub in ["scan", "count", "dedup", "run-all", "report"] {
        assert!(s.contains(sub), "--help missing subcommand `{sub}`");
    }
}

#[test]
fn scan_against_tiny_corpus_emits_findings() {
    let fixture = tempfile::tempdir().expect("tmp");
    let out_dir = tempfile::tempdir().expect("tmp out");
    let big = fixture.path().join("big.md");
    let payload = "# Big\n".repeat(2000);
    std::fs::write(&big, payload).unwrap();

    let status = Command::new(ctxopt_bin())
        .args([
            "scan",
            fixture.path().to_str().unwrap(),
            "--out-dir",
            out_dir.path().to_str().unwrap(),
            "--format",
            "jsonl",
            "--quiet",
        ])
        .status()
        .expect("ctxopt scan");
    assert!(status.success(), "ctxopt scan failed");

    let findings = out_dir.path().join("findings.jsonl");
    let body = std::fs::read_to_string(findings).expect("read findings.jsonl");
    assert!(body.contains("CTX-SCAN-"));
    assert!(body.contains("big.md"));
}

#[test]
fn run_all_writes_report_md_and_summaries() {
    let fixture = tempfile::tempdir().expect("tmp");
    let out_dir = tempfile::tempdir().expect("tmp out");
    std::fs::write(
        fixture.path().join("a.md"),
        "Lorem ipsum dolor sit amet consectetur adipiscing elit.\n".repeat(10),
    )
    .unwrap();
    std::fs::write(
        fixture.path().join("b.md"),
        "Lorem ipsum dolor sit amet consectetur adipiscing elit.\n".repeat(10),
    )
    .unwrap();

    let status = Command::new(ctxopt_bin())
        .args([
            "run-all",
            fixture.path().to_str().unwrap(),
            "--out-dir",
            out_dir.path().to_str().unwrap(),
            "--format",
            "toon",
            "--quiet",
        ])
        .status()
        .expect("ctxopt run-all");
    assert!(status.success(), "ctxopt run-all failed");

    assert!(out_dir.path().join("findings.toon").exists());
    assert!(out_dir.path().join("findings.jsonl").exists()); // sidecar for aggregation
    assert!(out_dir.path().join("summary.json").exists());
    assert!(out_dir.path().join("summary.toon").exists());
    assert!(out_dir.path().join("report.md").exists());

    let toon = std::fs::read_to_string(out_dir.path().join("findings.toon")).unwrap();
    assert!(
        toon.starts_with("findings["),
        "TOON header missing: {}",
        &toon[..toon.len().min(60)]
    );
}
