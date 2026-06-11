# Python Security Lifecycle (FastAPI / Django / Flask) — `code-security-review` Python branch reference

> Stack-specific reference loaded by `code-security-review/SKILL.md` Phase 0 when `pyproject.toml` (or `requirements.txt` / `setup.py`) is detected together with `fastapi`, `django`, or `flask`. Sibling references in this folder: `CONFIGURATION.md`, `PATCHES.md`, `TESTING_PAYLOADS.md`, `VULNERABILITIES.md`. Generic phases (`DESIGN_CONTROLS.md`, `TESTING_PHASES.md`, `WEB_VULNERABILITIES.md`, `REPORT_TEMPLATE.md`) live one directory up.

## When to Use

Load this reference when the parent skill is active and the project is detected as a Python web service on FastAPI 0.115+, Django 5.x, or Flask 3.x running on CPython 3.13 / 3.14. Use it when:

- Auditing a **FastAPI / Django / Flask** project for security issues
- Hardening a Python service before production rollout
- Reviewing **Pydantic Settings**, **Django settings**, **Flask `app.config`**, **ASGI middleware**, JWT layers, supply-chain manifests
- Mapping a Python web codebase against the **OWASP Web Top 10 2025** and **OWASP API Top 10 2023**
- Applying or validating fixes for Python-specific issues (pickle/yaml deserialization, SSTI in Jinja2, ALLOWED_HOSTS misconfig, `SECRET_KEY` exposure, JWT alg confusion, free-threaded data races on `python3.14t`)

This reference is **lifecycle-driven**: identification → analysis → correction → validation in a single workflow. The generic catalog (`../WEB_VULNERABILITIES.md`), design patterns (`../DESIGN_CONTROLS.md`), and active testing phases (`../TESTING_PHASES.md`) live one directory up — load them in addition to this file.

**Out of scope:**
- **Litestar / Starlite, aiohttp, Sanic, Tornado, Bottle, Quart** — Phase 0 falls back to the generic flow.
- **Stand-alone Starlette without FastAPI** — best-effort; many Starlette checks still apply but the framework-specific Pydantic / dependency-injection guidance is FastAPI-shaped.
- **Strawberry / Graphene GraphQL** — covered by `../WEB_VULNERABILITIES.md` GraphQL section.
- **gRPC, AsyncAPI, MessagePack-only services** — out of scope; reach for the protocol-specific tooling.

## Prerequisites

Install the following tools before starting an audit:

| Tool | Purpose | Install |
| --- | --- | --- |
| **Python 3.13+ / 3.14+** | toolchain (the audited project itself) | https://www.python.org/downloads/ or `uv python install 3.14` |
| **pip-audit** | CVE scan via PyPI Advisory DB | `pipx install pip-audit` |
| **safety** | secondary CVE DB | `pipx install safety` |
| **bandit** | SAST CWE-mapped | `pipx install bandit` |
| **semgrep** | polyglot SAST + Python rule packs | `pipx install semgrep` |
| **osv-scanner** | OSV cross-check (broader than PyPI Advisory) | `brew install osv-scanner` or `go install github.com/google/osv-scanner/cmd/osv-scanner/v2@latest` |
| **uv** | Astral package manager + lockfile audit | `pipx install uv` |
| **ruff** | lint pack `--select S` runs Bandit rules at sub-second speed | `pipx install ruff` |
| **httpx** / **curl** | active probing | `pipx install httpx[cli]` |
| **jwt_tool** | JWT alg confusion / kid attack | `git clone https://github.com/ticarpi/jwt_tool` |
| **k6** | load + free-threaded race trigger | `brew install k6` |
| **defusedxml** (target) | safe XML parsing | `pip install defusedxml` |
| **DOMPurify analog** | Jinja2 escapes by default; for HTML sanitization use `nh3` or `bleach` | `pip install nh3` |

Required access:

- [ ] Read access to the project source (`pyproject.toml`, `requirements*.txt`, `setup.py`, `*.lock`, `manage.py`, `app/**`, `settings.py`, `wsgi.py`, `asgi.py`)
- [ ] Permission to run `uv sync` / `pip install -e .` / `pytest`
- [ ] If active testing is in scope: a running instance of the app and **written authorization** to test it

## Phase 0 — Framework & Environment Detection

Detect the project's framework, Python version, ASGI server, and database driver before running the remaining phases. Run the steps in order and stop at the first conclusive match per category.

### 0.1 Project gate

```bash
# Confirm Python project
test -f pyproject.toml || test -f requirements.txt || test -f setup.py || {
    echo "ERROR: no Python project markers (pyproject.toml / requirements.txt / setup.py)"; exit 1
}
```

### 0.2 Framework detection

```bash
# Priority order — first match wins. Match anywhere on the line to handle
# both PEP 621 array form (`dependencies = ["fastapi>=0.115"]`) and
# poetry/requirements line form (`fastapi = "*"` / `fastapi==0.115`).
rg -q '\bfastapi\b' pyproject.toml requirements*.txt 2>/dev/null && echo "FW: fastapi"
rg -q '\bdjango\b'  pyproject.toml requirements*.txt 2>/dev/null && echo "FW: django"
rg -q '\bflask\b'   pyproject.toml requirements*.txt 2>/dev/null && echo "FW: flask"

# Confirm via the import graph
rg -q '^\s*from\s+fastapi\b|^\s*import\s+fastapi\b' --type py && echo "FW-confirmed: fastapi"
rg -q '^\s*from\s+django\b|DJANGO_SETTINGS_MODULE'  --type py && echo "FW-confirmed: django"
rg -q '^\s*from\s+flask\b|^\s*import\s+flask\b'     --type py && echo "FW-confirmed: flask"
```

Persist the result as `$FRAMEWORK ∈ {fastapi, django, flask, mixed, none}`. Phase 2 branches on this value.

### 0.3 Python version + free-threaded build

```bash
# Project requirement
rg 'requires-python\s*=\s*"[^"]+"' pyproject.toml
rg 'python_requires\s*=\s*"[^"]+"' setup.py setup.cfg 2>/dev/null
rg '^python\s*=' Pipfile 2>/dev/null

# Runtime
python --version          # the project's interpreter; ideally 3.13+
python -VV                # reveals "free-threading build" if applicable
```

Flag immediately if any of the following hold:
- Project pinned to `python_requires < 3.10` → multiple EOL CVEs upstream — **High**
- Production runs on `python3.14t` (free-threaded) without an audit of shared mutable state → **High**
- Project pinned to `python_requires >= 3.14` but a vendored C extension does not declare `Py_mod_gil = Py_MOD_GIL_NOT_USED` → **Medium** (forces GIL re-enable; not a vuln but a misconfiguration)

### 0.4 ASGI / WSGI server detection

```bash
rg -q 'uvicorn'    pyproject.toml requirements*.txt && echo "ASGI: uvicorn"
rg -q 'gunicorn'   pyproject.toml requirements*.txt && echo "WSGI/ASGI worker: gunicorn"
rg -q 'hypercorn'  pyproject.toml requirements*.txt && echo "ASGI: hypercorn"
rg -q 'daphne'     pyproject.toml requirements*.txt && echo "ASGI: daphne"
rg -q 'waitress'   pyproject.toml requirements*.txt && echo "WSGI: waitress"
```

Persist as `$SERVER ∈ {uvicorn, gunicorn, hypercorn, daphne, waitress, mixed, none}`. Affects Phase 2 (`CONFIGURATION.md` §8 ASGI server hardening).

### 0.5 Auth library detection

```bash
# FastAPI
rg -q 'fastapi-users|fastapi_users' pyproject.toml requirements*.txt && echo "AUTH: fastapi-users"
rg -q 'authlib|python-jose|pyjwt'   pyproject.toml requirements*.txt && echo "AUTH: jwt-stack (authlib / python-jose / pyjwt)"
# Django
rg -q 'django-allauth'              pyproject.toml requirements*.txt && echo "AUTH: django-allauth"
rg -q 'djangorestframework-simplejwt' pyproject.toml requirements*.txt && echo "AUTH: drf-simplejwt"
# Flask
rg -q 'flask-login|flask-security|flask-jwt-extended' pyproject.toml requirements*.txt && echo "AUTH: flask-login/security/jwt-extended"
```

Persist as `$AUTH ∈ {fastapi-users, jwt-stack, django-allauth, drf-simplejwt, flask-login, flask-security, flask-jwt-extended, custom, none}`. Phase 3 branches on this value.

### 0.6 Database / ORM detection

```bash
rg -q 'sqlalchemy'         pyproject.toml requirements*.txt && echo "ORM: sqlalchemy"
rg -q 'tortoise-orm'       pyproject.toml requirements*.txt && echo "ORM: tortoise"
rg -q '^\s*from\s+django\.db' --type py && echo "ORM: django"
rg -q 'peewee'             pyproject.toml requirements*.txt && echo "ORM: peewee"
rg -q 'asyncpg|psycopg|aiomysql|aiosqlite|motor|pymongo' pyproject.toml requirements*.txt
```

## Phase 1 — Static Security Audit

Run the automated toolchain first, then sweep for patterns the tools miss.

### 1.1 Automated toolchain

```bash
# Dependency CVE scan — primary
pip-audit --strict --format json --output pip-audit.json

# Secondary CVE DB
safety check --json --output safety.json

# OSV cross-check (broader than PyPI Advisory)
osv-scanner --lockfile=uv.lock        # or poetry.lock / Pipfile.lock / requirements.txt

# SAST — Bandit (CWE-mapped)
bandit -r src/ -q -f json -o bandit.json

# SAST — Ruff with Bandit rules (much faster than running bandit alone for incremental sweeps)
ruff check --select S src/ --output-format=json --output-file=ruff-security.json

# Semgrep with Python + framework rule packs
semgrep --config p/python --config p/owasp-top-ten --config p/django --config p/flask \
        --json --output semgrep.json src/

# Static type check (catches whole classes of API contract bugs that lead to security defects)
mypy --strict src/ 2>&1 | tee mypy.txt

# Secrets in repo
detect-secrets scan --all-files > secrets.json
```

Calibration: start every finding at **Medium** severity and promote to **High** only with manual confirmation. `pip-audit` and `safety` overlap; treat them as complementary, not duplicate.

### 1.2 Pattern sweep (manual)

For each category below, run the grep and read the matching files for context. Deep detail per item lives in [VULNERABILITIES.md](VULNERABILITIES.md).

| # | Category | Detection |
| --- | --- | --- |
| 1 | **Insecure deserialization** (pickle / marshal / yaml.load) | `rg -n '\b(pickle\|marshal)\.loads?\s*\(\|\byaml\.load\s*\(' --type py` |
| 2 | **SQL via f-string in execute** | `rg -n '(cursor\|conn\|db)\.execute\s*\(\s*f["\x27]' --type py` |
| 3 | **`subprocess(..., shell=True)`** | `rg -n 'subprocess\.(run\|call\|Popen)[^)]*shell\s*=\s*True' --type py` |
| 4 | **`eval` / `exec` / dynamic `compile`** | `rg -n '\b(eval\|exec\|compile)\s*\(' --type py` |
| 5 | **Jinja2 SSTI** | `rg -n 'Environment\([^)]*autoescape\s*=\s*False\|jinja2\.Template\(' --type py` |
| 6 | **XXE in `lxml` / `xml.etree`** | `rg -n 'lxml\.etree\.(parse\|fromstring\|XMLParser)\|xml\.(etree\|dom\|sax)\.' --type py` |
| 7 | **`requests.get(user_url)` / SSRF** | `rg -n '(requests\|httpx)\.(get\|post)\s*\([^)]*\b(request\.\|input\|params\|body)' --type py` |
| 8 | **Path traversal** | `rg -n 'open\s*\([^)]*os\.path\.join\([^)]*\b(request\|input\|args\|params\|body)' --type py` |
| 9 | **Hardcoded `SECRET_KEY` / `DEBUG=True`** | `rg -n 'SECRET_KEY\s*=\s*["\x27]\|DEBUG\s*=\s*True\|ALLOWED_HOSTS\s*=\s*\[\s*["\x27]\*' --type py` |
| 10 | **CORS `*` + credentials** | `rg -n 'allow_origins\s*=\s*\[\s*["\x27]\*\|allow_credentials\s*=\s*True' --type py` |
| 11 | **`random` for tokens** | `rg -n 'random\.(random\|choice\|randint\|sample\|shuffle)\(' --type py` |
| 12 | **Weak crypto (`md5` / `sha1` for security)** | `rg -n 'hashlib\.(md5\|sha1)\s*\(' --type py` |
| 13 | **Logger leaks `Authorization` / `password`** | `rg -n 'log(ger)?\.(info\|debug\|warning\|error)\s*\([^)]*\b(password\|token\|secret\|cookie\|authorization\|jwt)\b' --type py` |
| 14 | **Django pickle session serializer** | `rg -n 'SESSION_SERIALIZER\s*=\s*["\x27].*PickleSerializer' --type py` |
| 15 | **JWT `algorithms=["none"]` / weak alg list** | `rg -n 'jwt\.decode\([^)]*algorithms\s*=' --type py` |
| 16 | **FastAPI `/docs` / `/redoc` exposed in prod** | `rg -n 'FastAPI\(' --type py` — check for `docs_url=None` |
| 17 | **`tarfile.extractall` / ZIP slip** | `rg -n 'tarfile\.extractall\|zipfile\.ZipFile.*extractall' --type py` |
| 18 | **Blocking call inside `async def`** | `rg -n -B 2 -A 8 'async def' --type py \| rg 'time\.sleep\|requests\.\|psycopg2\|pymongo'` |
| 19 | **Pydantic `extra="allow"` (mass assignment)** | `rg -n 'model_config\s*=\s*ConfigDict\([^)]*extra\s*=\s*["\x27]allow["\x27]' --type py` |
| 20 | **`pickle` in Celery task body** | `rg -n -B 2 'CELERY_TASK_SERIALIZER\s*=\s*["\x27]pickle' --type py` |

## Phase 2 — Framework Configuration Audit

Branch on `$FRAMEWORK` from Phase 0. Full configuration snippets live in [CONFIGURATION.md](CONFIGURATION.md).

### 2.1 FastAPI — `FastAPI()` initialization

| Field | Expected | Anti-pattern (severity) |
| --- | --- | --- |
| `docs_url` | `None` in production | absent (defaults to `/docs`) — **High** (info disclosure + admin attack surface) |
| `redoc_url` | `None` in production | absent (defaults to `/redoc`) — **High** |
| `openapi_url` | `None` in production OR gated by auth | absent (`/openapi.json` public) — **High** |
| `default_response_class` | `ORJSONResponse` or default | uncaught exception leaks stack via default `JSONResponse` — see error handler |
| `dependencies` | Global `Depends(verify_auth)` for protected route groups | absent on protected routers — **High** |
| `middleware` | `CORSMiddleware`, `TrustedHostMiddleware`, security-headers middleware | any missing — **Medium** to **High** depending on item |

### 2.2 Django — `settings.py`

Mandatory checks:

- [ ] `DEBUG = False` in production (never read `DEBUG = os.environ.get(...)` with a default of `True`)
- [ ] `ALLOWED_HOSTS = ["..."]` is an explicit list (never `["*"]` in production)
- [ ] `SECRET_KEY` loaded from a secret manager / env var, never hardcoded; minimum 50 chars; rotated when leaked
- [ ] `SESSION_COOKIE_SECURE = True`, `SESSION_COOKIE_HTTPONLY = True`, `SESSION_COOKIE_SAMESITE = "Lax"` (or `"Strict"`)
- [ ] `CSRF_COOKIE_SECURE = True`, `CSRF_COOKIE_HTTPONLY = True` (post-1.10), `CSRF_COOKIE_SAMESITE = "Lax"`
- [ ] `SECURE_SSL_REDIRECT = True`, `SECURE_HSTS_SECONDS >= 31536000`, `SECURE_HSTS_INCLUDE_SUBDOMAINS = True`, `SECURE_HSTS_PRELOAD = True`
- [ ] `SECURE_CONTENT_TYPE_NOSNIFF = True`, `SECURE_BROWSER_XSS_FILTER` is **not** set (deprecated; use CSP)
- [ ] `X_FRAME_OPTIONS = "DENY"` (or `"SAMEORIGIN"` with justification)
- [ ] `SESSION_SERIALIZER` is `"django.contrib.sessions.serializers.JSONSerializer"` (PickleSerializer was deprecated in Django 4.1 and removed in 5.0; flag if still imported anywhere)
- [ ] `DATABASES` does not expose credentials in source — read from env
- [ ] `MIDDLEWARE` order: `SecurityMiddleware` first, `WhiteNoiseMiddleware` after `SecurityMiddleware`, `CommonMiddleware`, `CsrfViewMiddleware` (before any view-level middleware), `AuthenticationMiddleware`, `MessageMiddleware`, custom security middleware last

### 2.3 Flask — `app.config`

Mandatory checks:

- [ ] `app.config["SECRET_KEY"]` from env, ≥ 32 bytes, `secrets.token_urlsafe(48)` or higher entropy
- [ ] `app.config["SESSION_COOKIE_SECURE"] = True`, `SESSION_COOKIE_HTTPONLY = True`, `SESSION_COOKIE_SAMESITE = "Lax"`
- [ ] `app.config["PREFERRED_URL_SCHEME"] = "https"` when behind a TLS-terminating proxy
- [ ] `app.config["MAX_CONTENT_LENGTH"]` set (default = no limit → DoS risk)
- [ ] `Flask-WTF` `CSRFProtect(app)` wired for all state-changing routes (Flask does not ship CSRF protection by default)
- [ ] `Flask-Talisman` for HSTS, X-Frame-Options, Content-Type, Referrer-Policy headers + CSP with nonce
- [ ] `Flask-Limiter` initialized with explicit per-endpoint limits
- [ ] No `@app.errorhandler(Exception)` returning `str(e)` to the client

### 2.4 Security headers (verify with `curl -I https://target/`)

All frameworks should emit:

- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY` (or `SAMEORIGIN` with justification)
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- `Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-{nonce}'; ...`

See [CONFIGURATION.md](CONFIGURATION.md) §6 for per-framework header middleware templates.

### 2.5 CORS

```bash
# FastAPI / Starlette
rg -n -A 5 'CORSMiddleware\|add_middleware\(CORS' --type py
# Django
rg -n -A 3 'CORS_ALLOWED_ORIGINS\|CORS_ALLOW_ALL_ORIGINS\|CORS_ALLOW_CREDENTIALS' --type py
# Flask
rg -n -A 3 'CORS\(\|flask_cors\|cross_origin' --type py
```

Flag immediately (**Critical**) any combination of:
- `allow_origins=["*"]` AND `allow_credentials=True` (FastAPI / Flask)
- `CORS_ALLOW_ALL_ORIGINS = True` AND `CORS_ALLOW_CREDENTIALS = True` (Django)
- Origin reflected from the request header without an allowlist check
- This is the CVE-2025-34291 (Langflow) anti-pattern

### 2.6 Environment / secrets

```bash
# Find .env-style files that must NOT ship to git
ls -la .env .env.local .env.production 2>/dev/null
git ls-files | rg '\.env(\.local|\.production)?$'

# Cleartext secrets in code
rg -n '(SECRET_KEY|AWS_SECRET|API_KEY|TOKEN)\s*=\s*["\x27][A-Za-z0-9/+=_-]{16,}["\x27]' --type py
```

Required:
- [ ] `.env*` files in `.gitignore` and not committed
- [ ] Secrets loaded via `pydantic-settings.BaseSettings` (FastAPI / Flask) or `django-environ` (Django) — never `os.environ.get("X", "default-secret")`
- [ ] Secret rotation policy documented (if ever leaked, full history counts as leaked)

## Phase 3 — Authentication & Authorization Audit

Branch on `$AUTH` from Phase 0.

### 3.1 Common checks (all auth libraries)

Every state-changing endpoint must satisfy:

- [ ] Explicit auth check (`Depends(get_current_user)` / `@login_required` / `@jwt_required()`) before any handler body executes
- [ ] Explicit authorization check (resource ownership / RBAC) **before** any database mutation
- [ ] Input validated through Pydantic / Django Forms / `marshmallow` / `flask-pydantic` — TypeScript-style type annotations are **not** runtime checks
- [ ] Response models exclude sensitive fields (no `return user` with `password_hash`, `stripe_customer_id`, etc.) — explicit DTO
- [ ] Rate limit per `user_id` (or IP fallback) on auth endpoints
- [ ] GET endpoints do **not** mutate state (CSRF surface)
- [ ] Password storage uses `argon2-cffi` (preferred) or `passlib[bcrypt]` with cost ≥ 12
- [ ] Tokens generated with `secrets.token_urlsafe(32)` — never `random.choice` or `uuid.uuid4()` for security-sensitive contexts (UUIDv4 is acceptable for IDs, not for secrets)

### 3.2 Branch: FastAPI + JWT (`authlib` / `python-jose` / `pyjwt`)

- [ ] `jwt.decode(..., algorithms=["RS256"])` — explicit allowlist; **never** include `"none"` or both symmetric + asymmetric (key confusion attack: HS256 verify with RSA pubkey as shared secret)
- [ ] `audience` and `issuer` validated on every decode
- [ ] Token TTL ≤ 1 hour (access) / ≤ 30 days (refresh) with revocation list for refresh
- [ ] Signing key loaded from env / secret manager; rotated on schedule
- [ ] No JWT in URL query string (logs leak); use `Authorization: Bearer` header
- [ ] `python-jose` is in maintenance mode — recommend migrating to `pyjwt` ≥ 2.9 or `authlib` ≥ 1.3
- [ ] FastAPI `OAuth2PasswordBearer(tokenUrl="...", auto_error=True)` — never `auto_error=False` without a follow-up check

### 3.3 Branch: FastAPI + `fastapi-users`

- [ ] Latest stable release (`fastapi-users >= 14.0`) with `fastapi-users[sqlalchemy]` / `[beanie]` adapter matching the ORM
- [ ] Password validator enforced (`PasswordHelper(password_helper=...)`)
- [ ] OAuth provider state/nonce verified by the library; do **not** override the callback URL handler
- [ ] Email verification + password reset endpoints rate-limited externally (the library does not rate-limit)

### 3.4 Branch: Django (`django-allauth` / DRF SimpleJWT)

- [ ] `AUTH_PASSWORD_VALIDATORS` configured (MinLength ≥ 12, CommonPasswordValidator, NumericPasswordValidator)
- [ ] `PASSWORD_HASHERS` lists `Argon2PasswordHasher` first
- [ ] DRF `permission_classes = [IsAuthenticated]` global default; `permission_classes = [AllowAny]` only on explicit public endpoints
- [ ] DRF SimpleJWT: `ROTATE_REFRESH_TOKENS = True`, `BLACKLIST_AFTER_ROTATION = True`, `ALGORITHM = "RS256"` (asymmetric), `AUDIENCE` set
- [ ] `django-allauth`: `ACCOUNT_EMAIL_VERIFICATION = "mandatory"`, `ACCOUNT_USERNAME_BLACKLIST` set, rate-limit hooks installed
- [ ] CSRF token required on all unsafe HTTP methods (default Django behavior — flag any `@csrf_exempt` usage)

### 3.5 Branch: Flask (`flask-login` / `flask-jwt-extended` / `flask-security-too`)

- [ ] `flask-login`: `login_manager.session_protection = "strong"`, `REMEMBER_COOKIE_SECURE = True`, `REMEMBER_COOKIE_HTTPONLY = True`
- [ ] `flask-jwt-extended`: `JWT_ALGORITHM = "RS256"`, `JWT_DECODE_AUDIENCE` set, refresh-token blocklist enabled via `@jwt.token_in_blocklist_loader`
- [ ] `flask-security-too` (preferred over abandoned `flask-security`) with `SECURITY_PASSWORD_HASH = "argon2"`
- [ ] No `before_request` that decodes JWT without verifying signature

### 3.6 Cryptographic hygiene (all branches)

- [ ] `secrets.token_urlsafe(32)` / `secrets.token_hex(32)` for tokens, IDs, password reset codes — **never** `random.*` (CWE-338)
- [ ] `hmac.compare_digest()` for token comparisons — **never** `==`
- [ ] `argon2-cffi` `id=Argon2id, t=3, m=65536, p=4` (OWASP 2025 params) OR `bcrypt` cost ≥ 12
- [ ] `cryptography` library current (`>=43.0`) — no `pycrypto` (unmaintained), no `pycryptodome` API used insecurely (e.g., ECB mode)
- [ ] No custom crypto implementations — defer to `cryptography.hazmat` / `cryptography.fernet`

## Phase 4 — Dependency & Supply Chain Audit

```bash
# 1. Production-only CVE scan
pip-audit --strict --format json --output pip-audit.json
safety check --json --output safety.json

# 2. OSV cross-check
osv-scanner --lockfile=uv.lock      # or poetry.lock / Pipfile.lock / requirements.txt

# 3. Check what's outdated
uv pip list --outdated              # or: pip list --outdated

# 4. Lockfile integrity — unexpected churn is a red flag
git log --follow --oneline uv.lock poetry.lock Pipfile.lock requirements*.txt | head -20

# 5. Override / extra-index detection
rg -n '\[\[tool\.uv\.sources\]\]|extra-index-url|trusted-host' pyproject.toml requirements*.txt

# 6. Install script red flags — Python ecosystem equivalent is setup.py with arbitrary code
rg -n -B 2 -A 20 'def\s+setup\s*\(' setup.py 2>/dev/null
rg -n 'install_requires|post_install' setup.py setup.cfg 2>/dev/null

# 7. Source distributions (sdist) vs wheels — sdist runs arbitrary setup.py at install time
uv pip compile --dry-run --resolution=highest pyproject.toml 2>&1 | rg 'sdist'

# 8. Typosquat heuristic — packages with high name similarity to top-100 downloads
# (no built-in tool; use socket.dev / pypi-scout if available)
```

### Dependencies to flag automatically

| Dep | Severity | Reason | Replacement |
| --- | --- | --- | --- |
| `python-jose` | Medium | Maintenance mode, lagging on CVEs (CVE-2024-33663 algorithm confusion) | `pyjwt >= 2.9` or `authlib >= 1.3` |
| `pyyaml` with `yaml.load(stream)` (no Loader) | High | Insecure default; documented since 2017 | `yaml.safe_load(stream)` or migrate to `ruamel.yaml` |
| `requests < 2.32.0` | High | CVE-2024-35195 (cert verification bypass under specific options) | `requests >= 2.32.0` |
| `urllib3 < 2.2.2` | High | CVE-2024-37891 (proxy auth leak) | `urllib3 >= 2.2.2` |
| `cryptography < 43.0` | Medium | Multiple bundled OpenSSL CVEs | `cryptography >= 43.0` |
| `jinja2 < 3.1.5` | Medium | CVE-2024-56326 (SSTI via `xmlattr`) | `jinja2 >= 3.1.5` |
| `flask-cors < 5.0` | Medium | Maintainer abandoned briefly; behavior change in 5.x | `flask-cors >= 5.0` (or migrate to manual CORS) |
| `django < 4.2 (LTS)` / `django < 5.x` | Critical to Medium depending on age | Multiple CVEs in older series | `django >= 4.2.x LTS` or `>= 5.1` |
| `pycrypto` (any version) | Critical | Unmaintained since 2014 | `cryptography` or `pynacl` |
| `xmltodict < 0.13` | Low | DoS via deeply nested XML | `xmltodict >= 0.13` |
| `pillow < 10.3` | High | Multiple CVEs (CVE-2024-28219 buffer overflow) | `pillow >= 10.3` |
| `gunicorn < 22.0` | Medium | CVE-2024-1135 request smuggling | `gunicorn >= 22.0` |
| `python-multipart < 0.0.18` | Medium | DoS via boundary parsing | `python-multipart >= 0.0.18` |

**Lockfile MUST be committed.** Treat any uncommitted change to `uv.lock` / `poetry.lock` / `requirements.txt` as a supply chain incident — re-resolve and inspect the diff.

## Phase 5 — Concurrency & Runtime Audit

Issues unique to async Python and the free-threaded build.

### 5.1 Blocking call inside `async def`

```bash
rg -n -B 2 -A 8 'async def' --type py | rg 'time\.sleep|requests\.|open\(.*\.read\(\)|psycopg2|pymongo|subprocess\.run'
```

Severity floor: **High** on a request handler hot path. Fix in [PATCHES.md](PATCHES.md) §PATCH-A. Common offenders: `time.sleep` (use `asyncio.sleep`), `requests` (use `httpx.AsyncClient`), sync ORM (use `asyncpg`/`databases`/`motor`).

### 5.2 Async deadlock / leaked task

```bash
rg -n 'asyncio\.create_task\(' --type py     # check that returned handle is retained
rg -n 'asyncio\.run\(' --type py             # never call inside an already-running loop
rg -n 'threading\.Lock\(' --type py          # sync lock in async code is a smell
```

### 5.3 Pickle in Celery task body

```bash
rg -n 'CELERY_TASK_SERIALIZER\s*=\s*["\x27]pickle' --type py
rg -n 'CELERY_ACCEPT_CONTENT\s*=\s*\[.*pickle' --type py
rg -n 'app\.conf\.task_serializer\s*=\s*["\x27]pickle' --type py
```

Severity floor: **Critical**. CWE-502. Any worker that consumes pickle from an untrusted broker is an RCE primitive. Use `json` (default since Celery 4) or `msgpack`.

### 5.4 FastAPI `BackgroundTasks` without timeout

```bash
rg -n -B 2 -A 8 'BackgroundTasks\(\)' --type py
```

Severity floor: **Medium**. Long-running background tasks block worker shutdown; missing timeouts amplify DoS.

### 5.5 Free-threaded race (Python 3.13t / 3.14t)

`python3.14t` is **supported** per PEP 779 (Oct 2025); `python3.13t` remains **experimental** (pre-PEP 779 build). Race-condition behavior is identical on both — the GIL is dropped — but support status affects production-grading.

Audit shared mutable state when the deploy target is **either** free-threaded build:

```bash
# Module-level mutable globals
rg -n '^[A-Z_]+\s*=\s*(\[\]|\{\}|set\(\)|defaultdict|Counter\(\))' --type py

# Class attribute mutations
rg -n -B 1 -A 1 '\bself\.\w+\s*\+=\s*\d' --type py
rg -n '\.cache_clear\(\)\|\.cache_info\(\)' --type py     # functools.lru_cache is thread-safe in 3.14, but app-level caches may not be

# Threading primitives — should appear when free-threading is the target
rg -n 'threading\.(Lock|RLock|Semaphore|Event)\b' --type py
rg -n 'queue\.Queue\b' --type py
```

Severity floor: **High** for shared mutable state on `python3.14t` without an explicit lock or thread-safe primitive. Fix in [PATCHES.md](PATCHES.md) §PATCH-B.

## Phase 6 — Auto-Fix / Patch Generation

> **Default behavior: NEVER apply patches automatically.** Always present diffs first, group by severity, and require explicit user confirmation per group.

### Patch protocol

For every finding from Phases 1–5:

1. Generate a unified diff using the matching template from [PATCHES.md](PATCHES.md).
2. Tag the patch with a **risk classification**:
   - **SAFE** — isolated change, no API contract or behavior shift (e.g., `random` → `secrets`, `yaml.load` → `yaml.safe_load`, removing `DEBUG = True`).
   - **REVIEW** — affects auth, middleware, or shared code paths (e.g., adding `Depends(get_current_user)`, tightening CORS, swapping pickle session serializer in Django).
   - **BREAKING** — changes the public API contract or response shape (e.g., introducing a response DTO to prevent over-fetching, enforcing CSRF on previously-exempt routes).
3. Group diffs by severity in the Phase 8 report.
4. Prompt the user: *"Apply [Critical] and [High] SAFE patches now? Review REVIEW/BREAKING patches manually first."*

### Apply sequence

```bash
# For each confirmed patch, in severity order:
# 1. Apply via Edit tool (one file at a time, never bulk Write)
# 2. Build / install gate
uv pip install -e .                       # or: pip install -e .
# If install fails:
#   git restore <file>
#   re-emit the patch as "manual review required"
#   continue to next patch
```

### Post-patch validation

```bash
# Re-run the automated audit to verify findings are gone
pip-audit --strict
safety check
bandit -r src/ -q
semgrep --config p/python --config p/owasp-top-ten src/
osv-scanner --lockfile=uv.lock

# Type check
mypy --strict src/

# If tests exist
pytest -q
```

The skill must report any patch that introduced new findings or test failures and offer to revert via `git restore`.

## Phase 7 — Active Testing

For generic OWASP API Top 10 attack payloads (auth bypass, BOLA, SQLi, NoSQL injection, JWT confusion, CORS reflection, rate-limit bypass), use the generic [`../TESTING_PHASES.md`](../TESTING_PHASES.md) Phases 1–7. Do not duplicate them here.

This phase covers **Python-stack-specific** attacks not covered by the generic flow. All payloads live in [TESTING_PAYLOADS.md](TESTING_PAYLOADS.md):

| Attack | Triggers | Expected if vulnerable |
| --- | --- | --- |
| **Pickle / yaml RCE probe** | POST payload containing serialized RCE gadget to any endpoint accepting `application/x-python-pickle` or `application/x-yaml` | RCE (callback, file write, DNS exfil) |
| **FastAPI `/docs` exposure** | `GET /docs`, `/redoc`, `/openapi.json` | 200 with schema content (should be 404 in prod) |
| **Django `DEBUG=True` info leak** | `GET /<nonexistent>` | Full stack trace + settings dump |
| **Jinja2 SSTI** | URL param / form field with `{{7*7}}`, then `{{config.items()}}`, then `{{ ''.__class__.__mro__[1].__subclasses__() }}` | Rendered evaluation (49, config dump, subclass enumeration → RCE) |
| **JWT `alg=none` / `kid` injection** | Replay token with `alg=none` and re-signed; `kid` parameter pointing at attacker-controlled key URL | Token accepted; arbitrary claims |
| **ASGI request smuggling** | `Transfer-Encoding: chunked` + `Content-Length` desync | Two requests parsed as one or vice versa |
| **gunicorn slowloris** | Many concurrent connections sending headers byte-by-byte | Worker exhaustion before `--timeout-keep-alive` triggers |
| **CORS reflection** | `Origin: https://evil.example` | Response includes `Access-Control-Allow-Origin: https://evil.example` |
| **SQLi via `text()` escape hatch** | Parameter that reaches `sqlalchemy.text("SELECT ... WHERE x = '" + user + "'")` | Auth bypass / data exfil |
| **Pydantic `extra="allow"` mass assignment** | POST body with extra field that maps to a privileged column (`role`, `is_admin`) | Field persisted despite not being in the documented schema |
| **Path traversal via `StaticFiles` / `send_from_directory`** | `GET /static/../../etc/passwd` | File served |
| **ZIP slip upload** | Upload tarball / zip with `../../etc/cron.d/x` member | Extraction writes outside target dir |
| **Free-threaded race trigger** | `k6` hammering a counter endpoint on `python3.14t` | Lost updates / corrupted counter |

## Phase 8 — Security Report

Generate the report in **Report Format v1** (same schema as the sibling Go and Next.js branches).

```markdown
# Python Web Security Report — <project name>

## Executive Summary
- **Python version:** 3.14.x
- **Framework:** FastAPI 0.115.x / Django 5.x / Flask 3.x
- **ASGI server:** uvicorn + gunicorn workers
- **Auth library:** fastapi-users / jwt-stack (pyjwt + authlib) / django-allauth + drf-simplejwt / flask-login + flask-jwt-extended
- **Deploy target:** containerized (k8s) / serverless / bare-metal
- **Files audited:** N
- **Findings:** Critical X · High Y · Medium Z · Low W · Info V
- **OWASP Web Top 10 2025 categories affected:** N / 10
- **OWASP API Top 10 2023 categories affected:** N / 10
- **Patches generated:** P (S SAFE · R REVIEW · B BREAKING)
- **Patches applied:** A (post-confirmation)
- **Post-fix validation:** PASS / FAIL

## Findings Table

| ID | Severity | OWASP | CWE | File:Line | Title | Risk tag | Status |
|----|----------|-------|-----|-----------|-------|----------|--------|
| PY-001 | Critical | A08:2025 / API8:2023 | CWE-502 | `tasks.py:14` | `yaml.load(payload)` without SafeLoader on broker message | SAFE | Diff available |
| PY-002 | Critical | A03:2025 | CWE-1395 | `pyproject.toml:24` | `pyyaml < 6.0.2` + `python-jose` (CVE-2024-33663 JWT alg confusion) | SAFE | Patched |
| PY-003 | High | A01:2025 / API1:2023 | CWE-639 | `app/api/orders.py:42` | Endpoint missing ownership check (BOLA) | REVIEW | Diff available |
| PY-004 | High | A02:2025 | CWE-942 | `app/main.py:18` | CORS `allow_origins=["*"]` + `allow_credentials=True` | SAFE | Patched |

## Detailed Findings

### PY-001 — Critical — `yaml.load(payload)` without SafeLoader

- **OWASP:** A08:2025 Software or Data Integrity Failures / API8:2023 Security Misconfiguration
- **CWE:** CWE-502 (Deserialization of Untrusted Data)
- **Location:** `tasks.py:14`
- **Framework:** FastAPI worker consuming Celery messages
- **Description:** The Celery task body parses an incoming YAML message via `yaml.load(payload)` without a `Loader=SafeLoader`. PyYAML's default loader instantiates arbitrary Python objects from a YAML payload, enabling remote code execution when an attacker controls any source of broker messages.
- **Impact:** RCE on every worker that consumes from this queue. Pre-auth if the broker accepts external producers.
- **Evidence:**
  ```python
  @app.task
  def process_export(payload: str):
      data = yaml.load(payload)        # CWE-502 — instantiates arbitrary objects
      return run_export(data)
  ```
- **Fix (diff):**
  ```diff
  - data = yaml.load(payload)
  + data = yaml.safe_load(payload)
  ```
- **Risk tag:** SAFE
- **Post-fix test:**
  ```bash
  # Send a YAML !!python/object payload — expect ConstructorError, not execution
  python -c "import yaml; yaml.safe_load('!!python/object/apply:os.system [\"id\"]')"
  # → yaml.constructor.ConstructorError
  ```
- **References:** OWASP A08:2025, API8:2023, CWE-502, PYVULN-011

## OWASP Web Top 10 2025 Compliance Matrix

- [ ] **A01** Broken Access Control — 1 finding (PY-003)
- [ ] **A02** Security Misconfiguration — 1 finding (PY-004)
- [ ] **A03** Software Supply Chain Failures — 1 finding (PY-002)
- [x] **A04** Cryptographic Failures
- [x] **A05** Injection
- [x] **A06** Insecure Design
- [x] **A07** Authentication Failures
- [ ] **A08** Software or Data Integrity Failures — 1 finding (PY-001)
- [x] **A09** Logging & Alerting Failures
- [x] **A10** Mishandling of Exceptional Conditions

## OWASP API Top 10 2023 Compliance Matrix

- [ ] **API1** Broken Object Level Authorization — 1 finding (PY-003)
- [x] **API2** Broken Authentication
- [x] **API3** Broken Object Property Level Authorization
- [x] **API4** Unrestricted Resource Consumption
- [x] **API5** Broken Function Level Authorization
- [x] **API6** Unrestricted Access to Sensitive Business Flows
- [x] **API7** Server-Side Request Forgery
- [ ] **API8** Security Misconfiguration — 2 findings (PY-001, PY-004)
- [x] **API9** Improper Inventory Management
- [x] **API10** Unsafe Consumption of APIs

## Remediation Roadmap

1. **Critical (immediate):** PY-001, PY-002
2. **High (≤ 48h):** PY-003, PY-004
3. **Medium (next sprint):** ...
4. **Low (next refactor):** ...
```

### Severity reference

| Severity | CVSS Range | Example |
| --- | --- | --- |
| **Critical** | 9.0–10.0 | Pickle/yaml deserialization on broker message, `DEBUG=True` in production, `SECRET_KEY` committed, JWT `alg=none` accepted, pickle in Celery task body |
| **High** | 7.0–8.9 | Missing endpoint auth, CORS `*` + credentials, SSRF via `requests.get(user_url)`, SQLi via f-string, path traversal in `open()`, Jinja2 SSTI |
| **Medium** | 4.0–6.9 | Missing rate limit, missing security header, `python-jose` in maintenance mode, blocking sync call on async hot path, Pydantic `extra="allow"` |
| **Low** | 1.0–3.9 | `print()` in production, `from x import *`, outdated but non-vulnerable dependency, verbose error in staging |
| **Informational** | N/A | `from __future__ import annotations` on 3.14 (now redundant), `random.random()` outside security context, `asyncio.eager_task_factory` opt-in opportunity |

## Sibling references

- [`../DESIGN_CONTROLS.md`](../DESIGN_CONTROLS.md) — language-agnostic design controls (auth, CORS, headers, rate limit)
- [`../TESTING_PHASES.md`](../TESTING_PHASES.md) — 7-phase active testing flow
- [`../WEB_VULNERABILITIES.md`](../WEB_VULNERABILITIES.md) — 100-vuln catalog
- [`../REPORT_TEMPLATE.md`](../REPORT_TEMPLATE.md) — finding documentation template
- [`../golang/API.md`](../golang/API.md) — companion lifecycle for Gin/Fiber Go projects
- [`../nextjs/API.md`](../nextjs/API.md) — companion lifecycle for Next.js 16+ App Router projects
- For Python runtime debugging (async deadlocks, free-threaded races), see `@code-debugger` `references/PYTHON.md`
- For Python static code review (smells, type hints, perf sweep), see `@code-review` `references/PYTHON.md`
