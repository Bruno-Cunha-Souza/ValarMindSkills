#!/usr/bin/env bash
# Source-able helper for ValarMindSkills install scripts.
# Provides `ensure_rust` (installs rustup if absent) + `build_skill_binary` (cargo build per skill).
#
# Usage in install-*.sh:
#     source "$REPO_ROOT/scripts/_lib/ensure-rust.sh"
#     for d in "$dest_skills"/*/; do build_skill_binary "$d" || true; done

# Detect existing Rust toolchain. Source ~/.cargo/env quietly if it exists so
# subshells launched in fresh terminal sessions can pick up rustup-installed
# binaries without requiring a shell restart.
_ensure_rust_load_cargo_env() {
  if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env" >/dev/null 2>&1 || true
  fi
}

# Returns 0 if Rust is available (after attempt to install if missing); 1 if user declined.
ensure_rust() {
  _ensure_rust_load_cargo_env

  if command -v rustc >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
    return 0
  fi

  echo "[install] Rust toolchain not found."
  echo "[install] Skills with Rust crates (e.g. context-optimization) need cargo to build their binaries."

  # Non-interactive (CI / install-all.sh): respect VALARMIND_AUTO_INSTALL_RUST=1 to skip prompt.
  if [ "${VALARMIND_AUTO_INSTALL_RUST:-0}" = "1" ]; then
    yn="y"
  else
    read -rp "[install] Install Rust via rustup now? [Y/n] " yn
  fi

  case "$yn" in
    [nN]*)
      echo "[install] Skipping Rust install. Skills that need cargo will fall back gracefully."
      echo "[install] To install later: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
      return 1
      ;;
    *)
      if ! command -v curl >/dev/null 2>&1; then
        echo "[install] curl not found; cannot fetch rustup. Install curl or Rust manually."
        return 1
      fi
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || {
        echo "[install] rustup install failed."
        return 1
      }
      _ensure_rust_load_cargo_env
      ;;
  esac

  if command -v rustc >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
    return 0
  fi

  echo "[install] rustup completed but cargo still not on PATH. Open a new shell and re-run install."
  return 1
}

# Build a single skill's Rust crate, if any. Expects skill_dir/scripts/<crate-name>/Cargo.toml.
# Crate name is read from the Cargo.toml `[package] name` field.
# Outputs the release binary to skill_dir/scripts/bin/<bin-name>.
# Returns 0 if there's no crate (skill has no Rust), 0 on successful build,
# non-zero if Rust is unavailable or build fails.
build_skill_binary() {
  local skill_dir="$1"
  if [ -z "$skill_dir" ] || [ ! -d "$skill_dir" ]; then
    return 0
  fi

  local cargo_toml=""
  if [ -d "$skill_dir/scripts" ]; then
    cargo_toml="$(find "$skill_dir/scripts" -maxdepth 3 -name Cargo.toml -print -quit 2>/dev/null || true)"
  fi
  [ -z "$cargo_toml" ] && return 0   # skill has no Rust crate

  if ! ensure_rust; then
    echo "[install] Skipping cargo build for $(basename "$skill_dir") (no Rust available)."
    return 0
  fi

  local crate_dir scripts_dir bin_name
  crate_dir="$(dirname "$cargo_toml")"
  scripts_dir="$(dirname "$crate_dir")"
  bin_name="$(awk -F'"' '/^[[:space:]]*name[[:space:]]*=/{print $2; exit}' "$cargo_toml")"

  if [ -z "$bin_name" ]; then
    echo "[install] Could not parse crate name from $cargo_toml — skipping."
    return 0
  fi

  echo "[install] Building $bin_name (cargo build --release in $crate_dir) ..."
  if ! ( cd "$crate_dir" && cargo build --release ); then
    echo "[install] cargo build failed for $bin_name. Skill audit-mode will be unavailable."
    return 1
  fi

  mkdir -p "$scripts_dir/bin"
  cp "$crate_dir/target/release/$bin_name" "$scripts_dir/bin/$bin_name"
  chmod +x "$scripts_dir/bin/$bin_name"
  echo "[install] Installed $scripts_dir/bin/$bin_name"
}

# Iterate all skill dirs under a root and build binaries when Cargo.toml is present.
build_all_skill_binaries() {
  local skills_root="$1"
  if [ -z "$skills_root" ] || [ ! -d "$skills_root" ]; then
    return 0
  fi

  for skill_dir in "$skills_root"/*/; do
    [ -d "$skill_dir" ] || continue
    build_skill_binary "$skill_dir" || true   # don't abort the install on a single failure
  done
}
