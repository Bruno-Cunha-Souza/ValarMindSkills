# Python Web Stack Vulnerability Catalog (FastAPI / Django / Flask)

Catalog of Python-specific vulnerability patterns for use by `code-security-review` (Python branch — `references/python/API.md`). Each entry follows the same structure: ID, CWE, severity baseline, vulnerable snippet, fixed snippet, detection command, notes.

Use the IDs (`PYVULN-NNN`) when emitting findings in the security report so they can be cross-referenced.

## Index by Category

- Injection — PYVULN-001 to PYVULN-008
- Deserialization — PYVULN-009 to PYVULN-013
- Crypto & Secrets — PYVULN-014 to PYVULN-020
- Auth & Sessions — PYVULN-021 to PYVULN-026
- Configuration & Headers — PYVULN-027 to PYVULN-032
- SSRF & Network — PYVULN-033 to PYVULN-035
- File & Path — PYVULN-036 to PYVULN-038
- XML / XXE — PYVULN-039
- Async & Runtime — PYVULN-040 to PYVULN-043
- Supply Chain — PYVULN-044 to PYVULN-046

---

## Injection

### PYVULN-001 — SQL injection via f-string in `cursor.execute`
- **CWE:** CWE-89 (SQL Injection)
- **Severity:** Critical
- **Vulnerable:**
  ```python
  user_id = request.args.get("id")
  cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
  ```
- **Fixed:**
  ```python
  cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
  ```
- **Detection:** `rg -n '(cursor|conn|db)\.execute\s*\(\s*f["\x27]' --type py`
- **Notes:** Both `psycopg2`/`psycopg`, `sqlite3`, and `mysql-connector` accept parameterized queries with `%s` (psycopg / mysql) or `?` (sqlite) placeholders. Never `.format`, never f-string, never `+ concat`.

### PYVULN-002 — SQL injection via ORM raw escape hatch
- **CWE:** CWE-89
- **Severity:** Critical
- **Vulnerable (SQLAlchemy):**
  ```python
  from sqlalchemy import text
  session.execute(text("SELECT * FROM users WHERE email = '" + email + "'"))
  ```
- **Vulnerable (Django):**
  ```python
  User.objects.raw(f"SELECT * FROM users WHERE email = '{email}'")
  ```
- **Fixed (SQLAlchemy):**
  ```python
  session.execute(text("SELECT * FROM users WHERE email = :email"), {"email": email})
  ```
- **Fixed (Django):**
  ```python
  User.objects.raw("SELECT * FROM users WHERE email = %s", [email])
  ```
- **Detection:** `rg -n 'text\(["\x27].*\+|raw\(f["\x27]|objects\.raw\(' --type py`
- **Notes:** ORM auto-escaping only covers the ORM API. The raw escape hatch is opt-in and must use bound params.

### PYVULN-003 — Command injection via `subprocess(..., shell=True)`
- **CWE:** CWE-78 (OS Command Injection)
- **Severity:** Critical
- **Vulnerable:**
  ```python
  subprocess.run(f"ls {user_dir}", shell=True)
  os.system(f"convert {user_path} out.png")
  ```
- **Fixed:**
  ```python
  subprocess.run(["ls", user_dir])              # list form, no shell
  subprocess.run(["convert", user_path, "out.png"], check=True)
  ```
- **Detection:** `rg -n 'subprocess\.(run|call|Popen|check_output)[^)]*shell\s*=\s*True|os\.(system|popen)\s*\(' --type py`

### PYVULN-004 — Code injection via `eval` / `exec` / `compile`
- **CWE:** CWE-95 (Eval Injection)
- **Severity:** Critical
- **Vulnerable:**
  ```python
  result = eval(request.args["expr"])
  exec(user_code)
  ```
- **Fixed:** Refuse `eval`/`exec` on untrusted input. Use `ast.literal_eval` only when the expected input is a Python literal (int/str/list/dict/tuple). For sandboxed evaluation, isolate to a separate process with `seccomp`/`nsjail`.
- **Detection:** `rg -n '\b(eval|exec|compile)\s*\(' --type py`

### PYVULN-005 — Server-Side Template Injection (Jinja2 SSTI)
- **CWE:** CWE-1336 (SSTI)
- **Severity:** Critical
- **Vulnerable:**
  ```python
  from jinja2 import Environment
  env = Environment(autoescape=False)            # autoescape disabled
  template = env.from_string(request.args["template"])
  return template.render()
  ```
- **Fixed:**
  ```python
  from jinja2 import Environment, select_autoescape
  env = Environment(
      autoescape=select_autoescape(["html", "xml"]),
      # Never load templates from user input — load from a fixed loader
  )
  template = env.get_template("safe_template.html")
  return template.render(user_value=request.args["v"])    # value passed as data, not template
  ```
- **Detection:** `rg -n 'Environment\([^)]*autoescape\s*=\s*False|jinja2\.Template\(|Template\(.*request\.' --type py`
- **Notes:** Probe payloads escalate `{{7*7}}` → `{{config.items()}}` (Flask) → `{{ ''.__class__.__mro__[1].__subclasses__() }}` (RCE).

### PYVULN-006 — LDAP injection via unescaped filter
- **CWE:** CWE-90 (LDAP Injection)
- **Severity:** High
- **Vulnerable:**
  ```python
  ldap.search_s(base, scope, f"(uid={user_input})")
  ```
- **Fixed:**
  ```python
  from ldap.filter import escape_filter_chars
  ldap.search_s(base, scope, f"(uid={escape_filter_chars(user_input)})")
  ```
- **Detection:** `rg -n 'ldap\.search.*\bf["\x27]|ldap\.search.*\+' --type py`

### PYVULN-007 — XPath injection
- **CWE:** CWE-643 (XPath Injection)
- **Severity:** High
- **Vulnerable:**
  ```python
  tree.xpath(f"//user[name='{name}']/email")
  ```
- **Fixed:**
  ```python
  tree.xpath("//user[name=$name]/email", name=name)
  ```
- **Detection:** `rg -n 'xpath\(\s*f["\x27]|xpath\(.*\+' --type py`

### PYVULN-008 — HTTP header injection (CRLF)
- **CWE:** CWE-113 (HTTP Header Injection)
- **Severity:** High
- **Vulnerable:**
  ```python
  return Response(headers={"X-Forward-To": user_supplied})
  return redirect(f"/profile?msg={user_supplied}")
  ```
  Carriage return / line feed in `user_supplied` injects extra headers or splits the response.
- **Fixed:** Validate that the value matches `r"^[\x20-\x7E]+$"` (printable ASCII, no CR/LF). FastAPI / Starlette and modern Flask reject CRLF in header values; older versions and custom code may not.
- **Detection:** Manual — grep `rg -n 'Response\(.*headers=' --type py` and inspect.

---

## Deserialization

### PYVULN-009 — `pickle.loads` on untrusted input (RCE)
- **CWE:** CWE-502 (Deserialization of Untrusted Data)
- **Severity:** Critical
- **Vulnerable:**
  ```python
  data = pickle.loads(request.body)               # body controlled by attacker
  cached = pickle.loads(redis_value)              # Redis populated by another tenant
  ```
- **Fixed:** Refuse pickle for untrusted boundaries. Use JSON, msgpack, or protobuf. If you must deserialize untrusted data, use a structured schema parser (Pydantic, msgspec) that does not instantiate arbitrary classes.
- **Detection:** `rg -n '\bpickle\.loads?\s*\(' --type py`
- **Notes:** From Python docs: "The pickle module is **not secure** against erroneous or maliciously constructed data." Pickle gadgets exist in stdlib (`os.system` reachable via `__reduce__`).

### PYVULN-010 — `marshal.loads` on untrusted input
- **CWE:** CWE-502
- **Severity:** Critical
- **Vulnerable:** `marshal.loads(request.body)` — though documented as for internal use, it accepts crafted bytecode and can crash or RCE.
- **Fixed:** Do not use `marshal` for any external boundary. Replace with JSON / msgpack.
- **Detection:** `rg -n '\bmarshal\.loads?\s*\(' --type py`

### PYVULN-011 — `yaml.load` without `SafeLoader`
- **CWE:** CWE-502
- **Severity:** Critical
- **Vulnerable:**
  ```python
  config = yaml.load(open("user_supplied.yaml"))   # default Loader instantiates arbitrary objects
  ```
- **Fixed:**
  ```python
  config = yaml.safe_load(open("user_supplied.yaml"))
  ```
- **Detection:** `rg -n 'yaml\.load\s*\([^)]*\)' --type py | rg -v 'SafeLoader|safe_load'`
- **Notes:** `yaml.safe_load` only constructs scalars, lists, dicts. `yaml.full_load` is **still unsafe**.

### PYVULN-012 — `jsonpickle.decode` on untrusted input
- **CWE:** CWE-502
- **Severity:** Critical
- **Vulnerable:** `jsonpickle.decode(user_json)` — supports arbitrary object reconstruction, equivalent to pickle.
- **Fixed:** Use `json.loads` + explicit deserializer (Pydantic `model_validate_json`).
- **Detection:** `rg -n 'jsonpickle\.decode\(' --type py`

### PYVULN-013 — `dill.loads` on untrusted input
- **CWE:** CWE-502
- **Severity:** Critical
- **Vulnerable:** `dill.loads(payload)` — extends pickle to serialize more types, including lambdas; same RCE class.
- **Fixed:** Same as pickle — refuse on external boundaries.
- **Detection:** `rg -n '\bdill\.loads?\s*\(' --type py`

---

## Crypto & Secrets

### PYVULN-014 — `hashlib.md5` / `sha1` for security
- **CWE:** CWE-327 (Use of a Broken or Risky Cryptographic Algorithm)
- **Severity:** High (security context); Informational (non-security checksums)
- **Vulnerable:**
  ```python
  hashlib.md5(password.encode()).hexdigest()
  hashlib.sha1(api_key).hexdigest()
  ```
- **Fixed:** `hashlib.sha256` / `blake2b` for general hashes; `argon2-cffi` or `bcrypt` (cost ≥ 12) for passwords.
- **Detection:** `rg -n 'hashlib\.(md5|sha1)\s*\(' --type py`

### PYVULN-015 — `random.*` for security tokens / IDs
- **CWE:** CWE-338 (Use of Cryptographically Weak Pseudo-Random Number Generator)
- **Severity:** Critical
- **Vulnerable:**
  ```python
  token = "".join(random.choices(string.ascii_letters, k=32))    # predictable
  ```
- **Fixed:**
  ```python
  import secrets
  token = secrets.token_urlsafe(32)
  ```
- **Detection:** `rg -n 'random\.(random|choice|randint|sample|shuffle|choices|getrandbits)\(' --type py`
- **Notes:** `uuid.uuid4()` is acceptable for opaque IDs (uses `os.urandom` under the hood) but **not** for secrets where you control the format.

### PYVULN-016 — Hardcoded `SECRET_KEY` / API key
- **CWE:** CWE-798 (Use of Hard-coded Credentials)
- **Severity:** Critical
- **Vulnerable:**
  ```python
  SECRET_KEY = "django-insecure-c7^@5q*z..."
  STRIPE_API_KEY = "sk_live_..."
  ```
- **Fixed:** Load from env via `pydantic-settings` (FastAPI/Flask) or `django-environ` (Django). Fail closed if absent.
- **Detection:** `rg -n '(SECRET_KEY|AWS_SECRET|API_KEY|STRIPE_.*_KEY|TOKEN)\s*=\s*["\x27][A-Za-z0-9/+=_-]{16,}["\x27]' --type py`
- **Notes:** Git history counts as leaked — rotate even if you `git rm` the file. Use `detect-secrets` in pre-commit.

### PYVULN-017 — Django `SESSION_SERIALIZER = "PickleSerializer"`
- **CWE:** CWE-502
- **Severity:** Critical (when sessions are signed but pickle gadget is still executed on decode)
- **Vulnerable:** Any project still importing `django.contrib.sessions.serializers.PickleSerializer` (removed in Django 5.0; deprecated 4.1).
- **Fixed:** `SESSION_SERIALIZER = "django.contrib.sessions.serializers.JSONSerializer"`.
- **Detection:** `rg -n 'SESSION_SERIALIZER\s*=\s*["\x27].*PickleSerializer|PickleSerializer' --type py`

### PYVULN-018 — JWT algorithm confusion (`alg=none` / HS256 ↔ RS256)
- **CWE:** CWE-347 (Improper Verification of Cryptographic Signature)
- **Severity:** Critical
- **Vulnerable:**
  ```python
  # Library defaults to multiple algorithms — attacker switches to HS256
  jwt.decode(token, public_key, algorithms=["RS256", "HS256"])
  # OR no algorithm restriction (older pyjwt):
  jwt.decode(token, key, verify=False)
  jwt.decode(token, key)                          # alg=none accepted
  ```
- **Fixed:**
  ```python
  jwt.decode(
      token,
      public_key,
      algorithms=["RS256"],                       # explicit single-algorithm allowlist
      audience="my-service",
      issuer="https://auth.example.com",
      options={"require": ["exp", "iat", "iss", "aud"]},
  )
  ```
- **Detection:** `rg -n 'jwt\.decode\(' --type py -A 3 | rg 'algorithms\s*=' || echo "missing algorithms="`
- **Notes:** Classic attack: server expects RS256 (asymmetric, public key); attacker sends `{"alg":"HS256",...}` signed with the public key as HMAC secret. Allowing both algorithms enables this. `alg=none` is no longer accepted by modern `pyjwt` / `authlib` but old custom decoders may still allow it.

### PYVULN-019 — Weak password hash parameters
- **CWE:** CWE-916 (Use of Password Hash With Insufficient Computational Effort)
- **Severity:** High
- **Vulnerable:** `bcrypt.hashpw(pw, bcrypt.gensalt(rounds=4))` (cost too low); `PBKDF2-HMAC-SHA256` < 600,000 iterations or `PBKDF2-HMAC-SHA512` < 210,000 iterations (OWASP 2025 password storage cheat sheet).
- **Fixed:** `argon2-cffi` `id=Argon2id, t=3, m=65536, p=4` (OWASP 2025); or `bcrypt.gensalt(rounds=12)`.
- **Detection:** `rg -n 'bcrypt\.gensalt\(rounds\s*=\s*[1-9]\)|pbkdf2.*iterations\s*=\s*[0-9]{1,5}\b' --type py`

### PYVULN-020 — Plaintext password storage
- **CWE:** CWE-256 (Plaintext Storage of a Password)
- **Severity:** Critical
- **Vulnerable:** Storing `user.password = request.json["password"]`; comparing with `user.password == submitted`.
- **Fixed:** `argon2.PasswordHasher().hash(pw)` on registration; `.verify(stored, submitted)` on login.
- **Detection:** Manual — read auth model + login view; grep for `password\s*=\s*request\.` and `password\s*==\s*`.

---

## Auth & Sessions

### PYVULN-021 — FastAPI endpoint missing `Depends(get_current_user)`
- **CWE:** CWE-862 (Missing Authorization)
- **Severity:** Critical to High depending on data exposure
- **Vulnerable:**
  ```python
  @router.get("/orders/{order_id}")
  async def get_order(order_id: str):
      return await db.order.get(order_id)        # no auth check
  ```
- **Fixed:**
  ```python
  @router.get("/orders/{order_id}")
  async def get_order(order_id: str, user: User = Depends(get_current_user)):
      order = await db.order.get(order_id)
      if order.user_id != user.id:
          raise HTTPException(status_code=404)    # 404 over 403 to avoid enumeration
      return order
  ```
- **Detection:** `rg -n -B 1 -A 2 '@router\.(get|post|put|delete|patch)' --type py | rg -v 'Depends|require_user'`
- **Notes:** Router-level `dependencies=[Depends(...)]` covers all routes in the router; combine with per-route ownership checks.

### PYVULN-022 — Django view missing `@login_required` / DRF `permission_classes`
- **CWE:** CWE-862
- **Severity:** Critical to High
- **Vulnerable:**
  ```python
  def admin_dashboard(request):
      return render(request, "admin.html", {"users": User.objects.all()})
  ```
- **Fixed:**
  ```python
  from django.contrib.auth.decorators import login_required, permission_required
  @login_required
  @permission_required("auth.view_user", raise_exception=True)
  def admin_dashboard(request):
      ...
  ```
- **Detection:** Manual — list every view in `urls.py` and verify each has an auth decorator or class.

### PYVULN-023 — Flask route missing `@login_required`
- **CWE:** CWE-862
- **Severity:** Critical to High
- **Detection:** `rg -n -B 1 '@app\.(get|post|route)\(|@bp\.(get|post|route)\(' --type py | rg -v 'login_required'`

### PYVULN-024 — OAuth state / nonce missing
- **CWE:** CWE-352 (CSRF — applied to OAuth flow)
- **Severity:** High
- **Vulnerable:** OAuth callback handler accepts a code without verifying `state` (and `nonce` for OpenID Connect).
- **Fixed:** Generate `state = secrets.token_urlsafe(32)` on `/login`, store in session, compare on callback. For OIDC, also verify `nonce` claim in the id_token.
- **Detection:** Manual review of OAuth callback handlers.

### PYVULN-025 — JWT with no expiry / no audience
- **CWE:** CWE-613 (Insufficient Session Expiration)
- **Severity:** High
- **Vulnerable:** Tokens minted without `exp` claim; decoder does not validate `aud`/`iss`.
- **Fixed:**
  ```python
  payload = {"sub": user.id, "exp": now + timedelta(minutes=15), "aud": "my-service", "iss": "https://auth"}
  token = jwt.encode(payload, key, algorithm="RS256")
  ```
- **Detection:** Manual — read every `jwt.encode` and `jwt.decode` call.

### PYVULN-026 — Password reset token weak / not invalidated after use
- **CWE:** CWE-640 (Weak Password Recovery Mechanism)
- **Severity:** High
- **Vulnerable:** Reset tokens generated with `random`, no TTL, reusable.
- **Fixed:** `secrets.token_urlsafe(32)`, TTL ≤ 30 min, single-use (invalidate on success or first failed attempt). Email the link, never include the token in the page response.

---

## Configuration & Headers

### PYVULN-027 — `DEBUG = True` in production
- **CWE:** CWE-489 (Active Debug Code)
- **Severity:** Critical
- **Vulnerable:** Django `DEBUG = True`; FastAPI `app = FastAPI(debug=True)`; Flask `app.run(debug=True)`.
- **Fixed:** Read from env, default `False`, validate that production environment rejects `True` at startup.
- **Detection:** `rg -n 'DEBUG\s*=\s*True|debug\s*=\s*True' --type py`
- **Notes:** Django `DEBUG=True` renders full stack trace + settings dump (including `SECRET_KEY` when loaded from env var into the settings module) on any unhandled exception or 404. Primary impact is **information disclosure**; becomes an **RCE escalation path** when leaked `SECRET_KEY` is reused to forge signed sessions, password-reset tokens, or `django.core.signing` payloads — but escalation requires a second vulnerability and is not automatic.

### PYVULN-028 — `ALLOWED_HOSTS = ["*"]` (Django)
- **CWE:** CWE-20 (Improper Input Validation — Host header)
- **Severity:** High
- **Vulnerable:** Allows Host header injection → cache poisoning, password-reset link spoofing.
- **Fixed:** Explicit list of hostnames. Use environment-driven `ALLOWED_HOSTS = env.list("ALLOWED_HOSTS")`.
- **Detection:** `rg -n 'ALLOWED_HOSTS\s*=\s*\[\s*["\x27]\*' --type py`

### PYVULN-029 — FastAPI `/docs` / `/redoc` / `/openapi.json` exposed in production
- **CWE:** CWE-200 (Information Exposure)
- **Severity:** High
- **Vulnerable:** Default FastAPI instance ships `/docs`, `/redoc`, `/openapi.json` publicly.
- **Fixed:** `FastAPI(docs_url=None, redoc_url=None, openapi_url=None)` when `environment == "production"`. Optionally gate behind admin auth.
- **Detection:** `rg -n 'FastAPI\(' --type py -A 3 | rg -v 'docs_url\s*=\s*None'`

### PYVULN-030 — CORS `*` + credentials
- **CWE:** CWE-942 (Permissive Cross-domain Policy)
- **Severity:** Critical
- **Vulnerable:** `CORSMiddleware(allow_origins=["*"], allow_credentials=True, ...)` (FastAPI) / `CORS_ALLOW_ALL_ORIGINS = True` + `CORS_ALLOW_CREDENTIALS = True` (Django) / `CORS(app, origins="*", supports_credentials=True)` (Flask).
- **Fixed:** Explicit origin list; never wildcard with credentials.
- **Detection:** `rg -n 'allow_origins\s*=\s*\[\s*["\x27]\*|CORS_ALLOW_ALL_ORIGINS\s*=\s*True|origins\s*=\s*["\x27]\*' --type py`
- **Notes:** CVE-2025-34291 (Langflow) — same anti-pattern weaponized in the wild.

### PYVULN-031 — Missing security headers (HSTS / CSP / X-Frame-Options)
- **CWE:** CWE-693 (Protection Mechanism Failure)
- **Severity:** Medium
- **Vulnerable:** App returns 200 with no `Strict-Transport-Security`, `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`.
- **Fixed:** See `CONFIGURATION.md` §6 — middleware that emits all required headers.
- **Detection:** `curl -sI https://target/` and check the response headers.

### PYVULN-032 — `X-Frame-Options` default not set / `'unsafe-inline'` in CSP
- **CWE:** CWE-1021 (Improper Restriction of Rendered UI Layers)
- **Severity:** Medium
- **Fixed:** `X-Frame-Options: DENY` and CSP `frame-ancestors 'none'`; CSP `script-src 'self' 'nonce-{nonce}' 'strict-dynamic'` (no `'unsafe-inline'`).

---

## SSRF & Network

### PYVULN-033 — `requests.get(user_url)` without allowlist
- **CWE:** CWE-918 (Server-Side Request Forgery)
- **Severity:** High to Critical (Critical when reachable from a public endpoint)
- **Vulnerable:**
  ```python
  url = request.args["url"]
  return requests.get(url).text
  ```
- **Fixed:**
  ```python
  from urllib.parse import urlparse
  import ipaddress, socket

  ALLOWED_HOSTS = {"api.partner.example", "files.partner.example"}

  def safe_fetch(url: str) -> str:
      p = urlparse(url)
      if p.scheme not in {"https"}:
          raise ValueError("scheme")
      if p.hostname not in ALLOWED_HOSTS:
          raise ValueError("host")
      # Resolve once; reject private/link-local/loopback IPs
      ip = socket.gethostbyname(p.hostname)
      if ipaddress.ip_address(ip).is_private or ipaddress.ip_address(ip).is_loopback or ipaddress.ip_address(ip).is_link_local:
          raise ValueError("ip")
      return requests.get(url, timeout=5).text
  ```
- **Detection:** `rg -n '(requests|httpx)\.(get|post|put|delete)\s*\([^)]*\b(request\.|input|params|body|query)' --type py`
- **Notes:** AWS metadata: `http://169.254.169.254/latest/meta-data/iam/security-credentials/`. DNS rebinding bypasses simple hostname allowlists — resolve once, pin to the resolved IP.

### PYVULN-034 — `urllib.request` without scheme check
- **CWE:** CWE-918
- **Severity:** High
- **Vulnerable:** `urllib.request.urlopen(user_supplied_url)` — accepts `file://`, `ftp://`, `gopher://` schemes, enabling local file read or unexpected protocol abuse.
- **Fixed:** Validate scheme is `https` (or whitelist explicitly); prefer `httpx`/`requests` which default to HTTP only.

### PYVULN-035 — Redirect chase amplifying SSRF
- **CWE:** CWE-601 + CWE-918
- **Severity:** High
- **Vulnerable:** `requests.get(url, allow_redirects=True)` against a user URL — initial host passes allowlist, redirect goes to internal IP.
- **Fixed:** `requests.get(url, allow_redirects=False)` and follow manually with allowlist check on each hop, max-redirects ≤ 3.

---

## File & Path

### PYVULN-036 — Path traversal via `open(os.path.join(base, user_path))`
- **CWE:** CWE-22 (Path Traversal)
- **Severity:** High
- **Vulnerable:**
  ```python
  path = os.path.join(STATIC_DIR, request.args["file"])
  return send_file(path)
  ```
  Attacker sends `?file=../../etc/passwd`.
- **Fixed:**
  ```python
  from pathlib import Path
  base = Path(STATIC_DIR).resolve()
  candidate = (base / request.args["file"]).resolve()
  if not candidate.is_relative_to(base):
      abort(404)
  return send_file(candidate)
  ```
- **Detection:** `rg -n 'open\s*\([^)]*os\.path\.join\([^)]*\b(request|input|args|params|body)|send_file\([^)]*os\.path\.join' --type py`

### PYVULN-037 — ZIP slip / `tarfile.extractall` against user upload
- **CWE:** CWE-22
- **Severity:** High
- **Vulnerable:**
  ```python
  tarfile.open(upload).extractall(path=upload_dir)        # entries like ../../etc/cron.d/x
  zipfile.ZipFile(upload).extractall(upload_dir)
  ```
- **Fixed (Python 3.12+):**
  ```python
  tarfile.open(upload).extractall(path=upload_dir, filter="data")    # rejects abs paths, .., and special members
  ```
- **Fixed (manual, older Python):**
  ```python
  base = Path(upload_dir).resolve()
  with tarfile.open(upload) as tf:
      for member in tf.getmembers():
          dest = (base / member.name).resolve()
          if not dest.is_relative_to(base):
              raise ValueError(f"unsafe path: {member.name}")
      tf.extractall(path=upload_dir)
  ```
- **Detection:** `rg -n 'tarfile\.(open\([^)]*\)\s*\.extractall|extractall)|ZipFile\([^)]*\)\.extractall' --type py`
- **Notes:** Python 3.12+ deprecates the unfiltered `extractall`; 3.14 enforces `filter="data"` more strictly. Backport `filter` argument when on 3.12+.

### PYVULN-038 — Django `FileField` without validators
- **CWE:** CWE-434 (Unrestricted File Upload)
- **Severity:** High
- **Vulnerable:** `FileField()` accepts any extension / size; uploaded files served via `MEDIA_URL`.
- **Fixed:** Add `validators=[FileExtensionValidator(allowed_extensions=["jpg","png","pdf"])]`, `max_length`, MIME sniffing (`python-magic`), and content-type allowlist. Store outside the web root or serve via authenticated view, not `MEDIA_URL`.

---

## XML / XXE

### PYVULN-039 — XML External Entity (XXE) via `lxml` / `xml.etree`
- **CWE:** CWE-611 (XXE)
- **Severity:** High
- **Vulnerable:**
  ```python
  from lxml import etree
  tree = etree.fromstring(user_xml)                  # default parser resolves entities
  ```
- **Fixed:**
  ```python
  from lxml import etree
  parser = etree.XMLParser(resolve_entities=False, no_network=True, huge_tree=False)
  tree = etree.fromstring(user_xml, parser=parser)
  ```
  **Or use `defusedxml`:**
  ```python
  from defusedxml import ElementTree as ET
  tree = ET.fromstring(user_xml)
  ```
- **Detection:** `rg -n 'lxml\.etree\.(parse|fromstring|XMLParser)|xml\.(etree|dom|sax)\.' --type py`
- **Notes:** `defusedxml` is the safest default — it patches stdlib modules to refuse entity expansion and DTD loading. Add to `requirements.txt` if any XML is parsed.

---

## Async & Runtime

### PYVULN-040 — Blocking sync call in an async route
- **CWE:** CWE-400 (Uncontrolled Resource Consumption — event loop starvation)
- **Severity:** High on hot path
- **Vulnerable:**
  ```python
  @app.get("/data")
  async def data():
      time.sleep(2)
      return requests.get("https://upstream/").text
  ```
- **Fixed:**
  ```python
  import asyncio, httpx
  client = httpx.AsyncClient()

  @app.get("/data")
  async def data():
      await asyncio.sleep(2)
      r = await client.get("https://upstream/")
      return r.text
  ```
  Or wrap unavoidably-sync code in `asyncio.to_thread(sync_fn, arg)` / `loop.run_in_executor(None, sync_fn, arg)`.
- **Detection:** `rg -n -B 2 -A 8 'async def' --type py | rg 'time\.sleep|requests\.|psycopg2|pymongo|subprocess\.run|open\(.*\.read\(\)'`

### PYVULN-041 — `pickle` in Celery task body
- **CWE:** CWE-502
- **Severity:** Critical
- **Vulnerable:**
  ```python
  CELERY_TASK_SERIALIZER = "pickle"
  CELERY_ACCEPT_CONTENT = ["pickle"]
  ```
- **Fixed:**
  ```python
  CELERY_TASK_SERIALIZER = "json"
  CELERY_RESULT_SERIALIZER = "json"
  CELERY_ACCEPT_CONTENT = ["json"]
  ```
- **Detection:** `rg -n 'CELERY_TASK_SERIALIZER\s*=\s*["\x27]pickle|CELERY_ACCEPT_CONTENT.*pickle|app\.conf\.task_serializer\s*=\s*["\x27]pickle' --type py`
- **Notes:** Any worker pulling pickled jobs is RCE for whoever can publish to the broker. Default since Celery 4 is `json` — flag projects that re-enabled pickle.

### PYVULN-042 — FastAPI `BackgroundTasks` without timeout
- **CWE:** CWE-400
- **Severity:** Medium
- **Vulnerable:** `background_tasks.add_task(long_running_fn, ...)` without a timeout — blocks worker shutdown; missing timeouts amplify DoS.
- **Fixed:** Run via `asyncio.wait_for(task, timeout=N)` or push to a queue (Celery / arq / dramatiq) and respond immediately.

### PYVULN-043 — Free-threaded shared state without lock (`python3.14t` supported / `python3.13t` experimental)
- **CWE:** CWE-362 (Concurrent Execution using Shared Resource with Improper Synchronization)
- **Severity:** High
- **Vulnerable:** Module-level mutable state (`COUNTER = 0`, `CACHE = {}`, `SESSIONS = []`) read/written from multiple threads on a free-threaded build (`python3.14t` per PEP 779 supported; `python3.13t` still experimental) without `threading.Lock`. On GIL builds (`python3.13` / `python3.14`), the GIL serialized bytecode and hid the race.
- **Fixed:**
  ```python
  from threading import Lock

  _lock = Lock()
  CACHE: dict[str, int] = {}

  def increment(key: str) -> int:
      with _lock:
          CACHE[key] = CACHE.get(key, 0) + 1
          return CACHE[key]
  ```
  Or use thread-safe primitives: `queue.Queue`, `threading.local()`.
- **Detection:** `rg -n '^[A-Z_]+\s*=\s*(\[\]|\{\}|set\(\)|defaultdict|Counter\(\))' --type py` + check whether `python3.14t` is in the target.

---

## Supply Chain

### PYVULN-044 — Typosquat in `requirements.txt`
- **CWE:** CWE-829 (Inclusion of Functionality from Untrusted Control Sphere)
- **Severity:** Critical
- **Vulnerable:** `requirments.txt` (typo of `requirements`), `cloras` (typo of `colorama`), `python-dateutil2`, etc. — packages historically used in typosquat attacks.
- **Fixed:** Cross-check every dep name against the canonical PyPI page; pin to a known-good version; lock with `uv.lock` / `poetry.lock`. Use `pip-audit` and Socket.dev to flag suspicious newly-added deps.
- **Detection:** Manual; tools: `socket.dev`, `pypi-scout`.

### PYVULN-045 — Git dependency without rev / tag pin
- **CWE:** CWE-829
- **Severity:** High
- **Vulnerable:** `git+https://github.com/user/repo.git` (no rev) in `requirements.txt` or `pyproject.toml`. Repo owner can ship new code at any time.
- **Fixed:** Pin to a tag or commit SHA: `git+https://github.com/user/repo.git@v1.2.3` or `@<40-char-sha>`.
- **Detection:** `rg -n 'git\+https?://' pyproject.toml requirements*.txt | rg -v '@[a-f0-9]{40}|@v?[0-9]+\.[0-9]'`

### PYVULN-046 — Unpinned base image / Python runtime
- **CWE:** CWE-1357 (Reliance on Insufficiently Trustworthy Component)
- **Severity:** Medium
- **Vulnerable:** `FROM python:3` or `FROM python:3.14` in Dockerfile — floating tags change without notice.
- **Fixed:** Pin to a digest (`FROM python:3.14.5-slim@sha256:...`) or a fully-qualified patch tag and a renewal automation (Dependabot / Renovate).
- **Detection:** `rg -n '^FROM\s+python:' Dockerfile* | rg -v '@sha256:'`
