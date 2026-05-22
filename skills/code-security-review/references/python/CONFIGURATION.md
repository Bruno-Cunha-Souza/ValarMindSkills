# Python Web Stack Configuration Reference (FastAPI / Django / Flask)

Complete configuration patterns for the security items checked in Phase 2 of `code-security-review` (Python branch — `references/python/API.md`). This document is the Python equivalent of `references/golang/MIDDLEWARE.md` and `references/nextjs/CONFIGURATION.md`.

> **Scope:** CPython 3.13 / 3.14. FastAPI 0.115+, Django 5.x, Flask 3.x. ASGI: uvicorn / hypercorn. Worker: gunicorn + uvicorn workers. The free-threaded build (`python3.14t`) is called out where it changes a recommendation.

---

## 1. Pydantic Settings — Hardened Baseline (FastAPI / Flask)

```python
# app/settings.py
from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="forbid",                # Refuse unknown vars — flags typos and stale secrets
        case_sensitive=False,
    )

    # Mandatory secrets — fail closed if absent
    secret_key: SecretStr = Field(..., min_length=32)
    database_url: SecretStr = Field(...)
    jwt_private_key: SecretStr = Field(...)
    jwt_public_key: SecretStr = Field(...)

    # Tunables
    environment: str = Field(default="production")
    debug: bool = Field(default=False)
    allowed_origins: list[str] = Field(default_factory=list)
    rate_limit_per_minute: int = Field(default=100, ge=1, le=10_000)

    @field_validator("debug")
    @classmethod
    def reject_debug_in_prod(cls, v: bool, info) -> bool:
        env = info.data.get("environment", "production")
        if env == "production" and v:
            raise ValueError("DEBUG must be False in production")
        return v


settings = Settings()        # raises if env is incomplete
```

### Mandatory checks after applying

- [ ] `extra="forbid"` rejects unknown environment variables (catches typos and stale secrets).
- [ ] Secret fields use `SecretStr` — its `repr()` redacts the value.
- [ ] `min_length=32` on `secret_key` — enforces entropy at startup.
- [ ] `field_validator` rejects `debug=True` when `environment=production`.
- [ ] No `default="..."` for production secrets — fail closed.

---

## 2. FastAPI — Production-Hardened `FastAPI()`

```python
# app/main.py
from fastapi import FastAPI, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import ORJSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

from app.settings import settings
from app.security import require_user, security_headers_middleware

app = FastAPI(
    title="My Service",
    version="1.0.0",
    docs_url=None if settings.environment == "production" else "/docs",
    redoc_url=None if settings.environment == "production" else "/redoc",
    openapi_url=None if settings.environment == "production" else "/openapi.json",
    default_response_class=ORJSONResponse,
    # Global dependencies apply to every route — augment with router-level auth
    dependencies=[],
)

# 1. Trust the platform proxy headers (only inside a known proxy)
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=["api.example.com", "*.example.com"],
)

# 2. CORS — explicit allowlist; never `["*"]` with credentials
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
    max_age=600,
)

# 3. Security headers + per-request CSP nonce
app.add_middleware(BaseHTTPMiddleware, dispatch=security_headers_middleware)

# 4. Generic error handler — never leak stack traces
@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> Response:
    # log full detail server-side
    return ORJSONResponse(
        status_code=500,
        content={"error": "internal_error", "request_id": request.state.request_id},
    )

# 5. Routers — apply auth at the router level
from app.api.v1 import router as v1_router
app.include_router(v1_router, prefix="/v1", dependencies=[Depends(require_user)])
```

### Mandatory checks

- [ ] `docs_url=None` / `redoc_url=None` / `openapi_url=None` in production (or gated by an admin auth dependency).
- [ ] `TrustedHostMiddleware` configured (mitigates Host header injection).
- [ ] `CORSMiddleware` uses explicit origin list — never `["*"]` with credentials.
- [ ] Global exception handler returns a generic body — never `str(exc)` or `exc.__traceback__`.
- [ ] Routers apply auth dependencies at the include level for defense in depth.

---

## 3. Django — `settings.py` Hardened Baseline

```python
# settings.py — production
import environ

env = environ.Env(DEBUG=(bool, False))
environ.Env.read_env()

# === Secrets ===
SECRET_KEY = env("DJANGO_SECRET_KEY")              # min 50 chars; rotate on leak
DEBUG = env("DEBUG")                                # never True in production
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS")          # explicit list; never ["*"]

# === Database ===
DATABASES = {"default": env.db_url("DATABASE_URL")}

# === Sessions & CSRF cookies ===
SESSION_COOKIE_SECURE = True
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
SESSION_COOKIE_AGE = 60 * 60 * 2                   # 2 hours
SESSION_EXPIRE_AT_BROWSER_CLOSE = True
SESSION_SERIALIZER = "django.contrib.sessions.serializers.JSONSerializer"

CSRF_COOKIE_SECURE = True
CSRF_COOKIE_HTTPONLY = True
CSRF_COOKIE_SAMESITE = "Lax"
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS")

# === HTTPS / HSTS ===
SECURE_SSL_REDIRECT = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_HSTS_SECONDS = 31_536_000                   # 1 year
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

# === Browser headers ===
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "strict-origin-when-cross-origin"
SECURE_CROSS_ORIGIN_OPENER_POLICY = "same-origin"
X_FRAME_OPTIONS = "DENY"

# === Password hashers ===
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
    "django.contrib.auth.hashers.BCryptSHA256PasswordHasher",
]

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
     "OPTIONS": {"min_length": 12}},
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# === Middleware order matters — security first ===
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",            # if used
    "django.contrib.sessions.middleware.SessionMiddleware",
    "corsheaders.middleware.CorsMiddleware",                 # before CommonMiddleware
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "csp.middleware.CSPMiddleware",                          # django-csp
    "app.middleware.SecurityHeadersMiddleware",              # custom
]

# === CORS (django-cors-headers) ===
CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS")    # explicit list
CORS_ALLOW_CREDENTIALS = True
CORS_ALLOW_ALL_ORIGINS = False                              # NEVER True with credentials

# === CSP (django-csp) ===
CSP_DEFAULT_SRC = ("'self'",)
CSP_SCRIPT_SRC = ("'self'", "'strict-dynamic'")             # use nonces for inline
CSP_STYLE_SRC = ("'self'",)
CSP_INCLUDE_NONCE_IN = ("script-src",)
CSP_IMG_SRC = ("'self'", "data:", "https:")
CSP_FRAME_ANCESTORS = ("'none'",)
CSP_BASE_URI = ("'self'",)
CSP_FORM_ACTION = ("'self'",)

# === Logging — never log secrets ===
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {"redact": {"()": "app.logging.RedactSecretsFilter"}},
    "handlers": {
        "console": {"class": "logging.StreamHandler", "filters": ["redact"]},
    },
    "root": {"handlers": ["console"], "level": "INFO"},
}
```

### Mandatory checks

- [ ] `DEBUG = False`, `ALLOWED_HOSTS` explicit list.
- [ ] All `SESSION_COOKIE_*` and `CSRF_COOKIE_*` security flags set.
- [ ] HSTS at least 1 year, `INCLUDE_SUBDOMAINS=True`, `PRELOAD=True`.
- [ ] `SESSION_SERIALIZER = "JSONSerializer"` — never the deprecated `PickleSerializer`.
- [ ] `Argon2PasswordHasher` first in `PASSWORD_HASHERS`.
- [ ] `CORS_ALLOW_ALL_ORIGINS = False` when `CORS_ALLOW_CREDENTIALS = True`.
- [ ] `CSP` configured with nonce; `frame-ancestors 'none'`.

---

## 4. Flask — Hardened Baseline

```python
# app/__init__.py
from flask import Flask
from flask_talisman import Talisman
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_wtf.csrf import CSRFProtect
from flask_cors import CORS

import secrets


def create_app(config: dict) -> Flask:
    app = Flask(__name__)
    app.config.update(config)

    # Mandatory config
    app.config.setdefault("SECRET_KEY", secrets.token_urlsafe(48))   # fail loud if absent
    app.config.update(
        SESSION_COOKIE_SECURE=True,
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        PERMANENT_SESSION_LIFETIME=60 * 60 * 2,             # 2 hours
        PREFERRED_URL_SCHEME="https",
        MAX_CONTENT_LENGTH=10 * 1024 * 1024,                # 10 MB body cap
        JSON_SORT_KEYS=False,
        WTF_CSRF_TIME_LIMIT=3600,
    )

    # 1. CSRF
    CSRFProtect(app)

    # 2. Security headers + CSP via Talisman
    Talisman(
        app,
        content_security_policy={
            "default-src": "'self'",
            "script-src": ["'self'", "'strict-dynamic'"],
            "style-src": "'self'",
            "img-src": ["'self'", "data:"],
            "frame-ancestors": "'none'",
            "base-uri": "'self'",
            "form-action": "'self'",
        },
        content_security_policy_nonce_in=["script-src"],
        force_https=True,
        strict_transport_security=True,
        strict_transport_security_max_age=31_536_000,
        strict_transport_security_include_subdomains=True,
        strict_transport_security_preload=True,
        session_cookie_secure=True,
        referrer_policy="strict-origin-when-cross-origin",
        # Talisman 1.x+: `feature_policy=` is deprecated; use `permissions_policy=` instead.
        # Omit the old kwarg entirely on fresh deploys.
        permissions_policy={
            "camera": "()", "microphone": "()", "geolocation": "()",
        },
    )

    # 3. Rate limiting
    Limiter(
        app=app,
        key_func=get_remote_address,             # IP fallback; prefer user_id when authed
        default_limits=["100/minute"],
        storage_uri="redis://localhost:6379/1",
        strategy="moving-window",
    )

    # 4. CORS — explicit allowlist
    CORS(
        app,
        origins=app.config["ALLOWED_ORIGINS"],
        supports_credentials=True,
        methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
        max_age=600,
    )

    # 5. Generic error handler — never expose internals
    @app.errorhandler(Exception)
    def handle_unexpected(exc):
        app.logger.exception("unhandled exception")
        return {"error": "internal_error"}, 500

    return app
```

### Mandatory checks

- [ ] `SECRET_KEY` from env / secret manager, ≥ 32 bytes entropy.
- [ ] All `SESSION_COOKIE_*` security flags set.
- [ ] `MAX_CONTENT_LENGTH` set (default = no limit → DoS).
- [ ] `Flask-WTF` `CSRFProtect(app)` wired before any state-changing route.
- [ ] `Flask-Talisman` headers + CSP with nonce.
- [ ] `Flask-Limiter` initialized with storage backend.
- [ ] No `@app.errorhandler(Exception)` returning `str(exc)`.

---

## 5. CORS — Three-Way Table

| Aspect | FastAPI (`CORSMiddleware`) | Django (`django-cors-headers`) | Flask (`flask-cors`) |
| --- | --- | --- | --- |
| Allowlist origins | `allow_origins=["https://app.example.com"]` | `CORS_ALLOWED_ORIGINS = ["https://app.example.com"]` | `CORS(app, origins=["https://app.example.com"])` |
| Credentials | `allow_credentials=True` | `CORS_ALLOW_CREDENTIALS = True` | `CORS(app, supports_credentials=True)` |
| All methods | `allow_methods=["GET","POST","PUT","DELETE","PATCH","OPTIONS"]` | `CORS_ALLOW_METHODS` (default sane) | `methods=["GET","POST","PUT","DELETE","PATCH","OPTIONS"]` |
| Preflight cache | `max_age=600` | `CORS_PREFLIGHT_MAX_AGE = 600` | `max_age=600` |
| Wildcard + credentials | **REJECTED** in FastAPI 0.115+ (silently downgraded; flag anyway) | **REJECTED** by `django-cors-headers` (raises) | **NOT REJECTED** — must audit manually |
| Origin regex | `allow_origin_regex=r"https://.*\.example\.com$"` | `CORS_ALLOWED_ORIGIN_REGEXES` | not supported natively |

**Forbidden combinations — all stacks:**
- `origins=["*"]` + `credentials=True`
- Origin reflected from `Origin` header without an allowlist check
- Allowlist that includes user-supplied subdomain (e.g., `*.example.com` when users register subdomains)

---

## 6. Security Headers Middleware

### 6.1 FastAPI / Starlette — `BaseHTTPMiddleware` with per-request CSP nonce

```python
# app/security.py
import secrets
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response


async def security_headers_middleware(request, call_next) -> Response:
    nonce = secrets.token_urlsafe(16)
    request.state.csp_nonce = nonce

    response: Response = await call_next(request)

    response.headers["Strict-Transport-Security"] = (
        "max-age=31536000; includeSubDomains; preload"
    )
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = (
        "camera=(), microphone=(), geolocation=()"
    )
    response.headers["Content-Security-Policy"] = (
        f"default-src 'self'; "
        f"script-src 'self' 'nonce-{nonce}' 'strict-dynamic'; "
        f"style-src 'self' 'nonce-{nonce}'; "
        f"img-src 'self' data: https:; "
        f"object-src 'none'; "
        f"base-uri 'self'; "
        f"form-action 'self'; "
        f"frame-ancestors 'none'; "
        f"upgrade-insecure-requests"
    )
    return response
```

### 6.2 Django — `SecurityMiddleware` + `django-csp`

Built-in `django.middleware.security.SecurityMiddleware` applies HSTS, content-type, and SSL redirect via the `SECURE_*` settings (see §3). For CSP, install `django-csp` and configure `CSP_*` settings (see §3). Both work together.

### 6.3 Flask — `Flask-Talisman`

See §4. Talisman handles HSTS, CSP, Referrer-Policy, Permissions-Policy, and X-Frame-Options out of the box.

### Required headers — verify with `curl -I https://target/`

- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- `Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-{nonce}' 'strict-dynamic'; ...`

---

## 7. Rate Limiting

| Stack | Library | Storage | Per-user key |
| --- | --- | --- | --- |
| FastAPI / Starlette | `slowapi` | Redis (`redis-py`) | `key_func=lambda r: r.state.user_id or get_remote_address(r)` |
| Django | `django-ratelimit` (decorator) or `drf-ratelimit` | Cache framework (Redis backend) | `key="user_or_ip"` |
| Flask | `Flask-Limiter` | Redis / Memcached | `key_func=lambda: g.user_id or get_remote_address()` |

### 7.1 FastAPI — SlowAPI

```python
# app/ratelimit.py
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from fastapi import Request

def user_or_ip(request: Request) -> str:
    return getattr(request.state, "user_id", None) or get_remote_address(request)

limiter = Limiter(key_func=user_or_ip, default_limits=["100/minute"], storage_uri="redis://localhost:6379/2")

# Register in main.py
# app.state.limiter = limiter
# app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Usage at the route
# @router.post("/login")
# @limiter.limit("5/15minutes")
# async def login(request: Request, ...): ...
```

### 7.2 Django — `django-ratelimit`

```python
# views.py
from django_ratelimit.decorators import ratelimit
from django.http import HttpResponseTooManyRequests

@ratelimit(key="user_or_ip", rate="5/15m", method="POST", block=True)
def login(request):
    ...
```

### 7.3 Flask — `Flask-Limiter`

```python
# blueprints/auth.py
from flask import Blueprint, g
from app.extensions import limiter

bp = Blueprint("auth", __name__)

@bp.post("/login")
@limiter.limit("5/15 minutes", key_func=lambda: g.user_id or get_remote_address())
def login():
    ...
```

### Algorithm choice

- **Sliding window** — strictest fairness; recommended for auth endpoints.
- **Token bucket** — bursty traffic friendly; recommended for general API.
- **Fixed window** — simplest; only acceptable for low-stakes endpoints (has boundary burst issue).

### Key strategy

- **Always prefer `user_id`** over IP. IP-only limits are bypassable via residential proxies and hurt shared-NAT users.
- **IP fallback** for unauthenticated routes (login, signup, password reset).
- **Validate the source IP** — `X-Forwarded-For` is only trustworthy when the proxy strips it on ingress; configure `SECURE_PROXY_SSL_HEADER` (Django) / `ProxyHeadersMiddleware` (FastAPI) / `ProxyFix` (Flask) so `request.client.host` reflects the real client.
- **Include the action type in the prefix** (`rl:email:{user_id}` vs `rl:export:{user_id}`) so limits are scoped per action.

---

## 8. ASGI / WSGI Server Hardening

### 8.1 Uvicorn (ASGI — FastAPI / Starlette)

```bash
uvicorn app.main:app \
    --host 0.0.0.0 --port 8000 \
    --workers 4 \
    --proxy-headers \
    --forwarded-allow-ips="10.0.0.0/8,127.0.0.1" \
    --limit-concurrency 1024 \
    --limit-max-requests 10000 \
    --timeout-keep-alive 5 \
    --timeout-graceful-shutdown 30 \
    --log-level info \
    --access-log \
    --no-server-header
```

Mandatory:
- [ ] `--proxy-headers` only behind a trusted proxy; `--forwarded-allow-ips` restricts which proxies can set `X-Forwarded-*`.
- [ ] `--limit-concurrency` and `--limit-max-requests` bound resource usage.
- [ ] `--timeout-keep-alive` prevents slowloris; `--timeout-graceful-shutdown` allows in-flight requests to finish on rolling deploy.
- [ ] `--no-server-header` removes the `Server: uvicorn` banner.

### 8.2 Gunicorn + Uvicorn Worker (recommended production)

```bash
gunicorn app.main:app \
    --worker-class uvicorn.workers.UvicornWorker \
    --workers 4 \
    --bind 0.0.0.0:8000 \
    --timeout 60 \
    --graceful-timeout 30 \
    --keep-alive 5 \
    --max-requests 10000 \
    --max-requests-jitter 500 \
    --access-logfile - \
    --error-logfile - \
    --forwarded-allow-ips="10.0.0.0/8,127.0.0.1"
```

Mandatory:
- [ ] `--worker-class uvicorn.workers.UvicornWorker` (for FastAPI/Starlette) or `gthread` (for Django/Flask sync).
- [ ] `--max-requests` + `--max-requests-jitter` rotate workers periodically (mitigates slow memory leaks; jitter prevents thundering herd).
- [ ] `--timeout` matches the longest legitimate request (avoid 30s defaults that mask slow handlers).
- [ ] Gunicorn ≥ 22.0 (CVE-2024-1135 request smuggling).

### 8.3 Hypercorn (HTTP/2 + ASGI)

```bash
hypercorn app.main:app \
    --bind 0.0.0.0:8000 \
    --workers 4 \
    --keep-alive 5 \
    --graceful-timeout 30 \
    --access-logfile - \
    --error-logfile -
```

---

## 9. Free-Threaded Build (`python3.14t`) — Deployment Caveats

Python 3.14 promotes the free-threaded build from experimental to supported (PEP 779). Production deployment requires careful audit.

| Concern | Mitigation |
| --- | --- |
| Single-threaded code runs ~5–10% slower on `python3.14t` vs `python3.14` | Benchmark both; deploy free-threaded only when concurrent throughput matters. |
| C extensions that did not declare `Py_mod_gil = Py_MOD_GIL_NOT_USED` force the GIL back on at import | Audit every wheel: `python -c 'import <pkg>; import sys; print(sys.flags.gil)'` — `1` means GIL re-enabled. Upgrade or replace extensions still on the GIL. |
| Module-level mutable state (caches, counters) races without GIL serialization | Wrap shared mutables with `threading.Lock` / `RLock` or use `queue.Queue` / `threading.local()`. |
| `dict.setdefault` / `Counter.update` are **not** atomic on the free-threaded build | Convert to explicit lock-protected sections; use `collections.defaultdict` with a `Lock` if needed. |
| `functools.lru_cache` is thread-safe in 3.14 but app-level caches built on dicts are not | Migrate to `functools.lru_cache` or `cachetools` with `threading.Lock` wrapper. |
| Workers under `gunicorn` with thread-based workers (`gthread`) suddenly run threads in parallel | Restrict to `sync` workers (Django/Flask) or `UvicornWorker` (FastAPI) until the application is audited. |

Recommended phased rollout: shadow traffic to `python3.14t` workers for ≥ 7 days, watch `tracemalloc` snapshots for divergent allocations, then graduate after one full release cycle.

---

## 10. Anti-patterns to flag immediately

- `FastAPI()` without `docs_url=None` in production (NEXTJS-vuln analog: `/docs` exposed).
- `Settings` class without `extra="forbid"` (unknown env vars silently ignored — typos and stale secrets pass).
- `app.config["SECRET_KEY"] = "dev-secret"` (hardcoded default, even in `config_dev.py`).
- `DEBUG = True` anywhere reachable in production code path.
- `ALLOWED_HOSTS = ["*"]` in any production-tagged settings module.
- `CORS_ALLOW_ALL_ORIGINS = True` combined with `CORS_ALLOW_CREDENTIALS = True`.
- `SESSION_SERIALIZER = "django.contrib.sessions.serializers.PickleSerializer"` (deprecated; pickle RCE class).
- `Talisman(force_https=False)` in production (downgrade attack surface).
- `CSRFProtect` not registered, or `@csrf_exempt` without a documented justification.
- Manual `Access-Control-Allow-Origin: *` returned from a custom decorator (bypasses framework CORS).
- `gunicorn` without `--max-requests` (leaked memory accumulates indefinitely).
- `uvicorn --reload` or `gunicorn --reload` in production manifests (CVE class: file watcher in prod).
