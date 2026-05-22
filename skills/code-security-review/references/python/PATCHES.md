# Python Web Stack Security Patch Templates

Patch templates for the auto-fix phase of `code-security-review` (Python branch — `references/python/API.md` Phase 6). Each template is keyed to a `PYVULN-NNN` ID from `VULNERABILITIES.md`.

Risk tag legend:
- **SAFE** — isolated change, no API contract or behavior shift, no shared state mutation.
- **REVIEW** — affects auth, middleware, or shared code paths; needs human inspection.
- **BREAKING** — changes the public API contract, response shape, or third-party integration; requires coordination with consumers.

Every patch must pass `pip install -e .` (or `uv sync`) and `pytest -q` before the skill marks it as applied. If install or tests fail, the change is reverted with `git restore <file>` and re-emitted as "manual review required".

---

## PATCH-001 — Parameterize SQL query (PYVULN-001)

**Risk:** SAFE
**Validation:** `pytest tests/test_sql.py -q`, then replay the SQLi probe with `' OR 1=1 --` — expect 400 / 404 / empty result, not the full table.

```diff
- cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
+ cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
```

For SQLAlchemy raw:

```diff
- session.execute(text("SELECT * FROM users WHERE email = '" + email + "'"))
+ session.execute(text("SELECT * FROM users WHERE email = :email"), {"email": email})
```

For Django ORM raw:

```diff
- User.objects.raw(f"SELECT * FROM users WHERE email = '{email}'")
+ User.objects.raw("SELECT * FROM users WHERE email = %s", [email])
```

Notes: same parameter style works across `psycopg2`, `psycopg3`, `mysql-connector-python`. `sqlite3` uses `?` instead of `%s`.

---

## PATCH-002 — Remove `shell=True` / migrate to list form (PYVULN-003)

**Risk:** REVIEW (changes argument passing — verify no downstream consumer parsed the shell string).
**Validation:** Run the calling endpoint with a payload containing `; rm -rf /` — expect literal filename, not shell execution.

```diff
- subprocess.run(f"ls {user_dir}", shell=True)
+ subprocess.run(["ls", user_dir], check=True)

- os.system(f"convert {user_path} out.png")
+ subprocess.run(["convert", user_path, "out.png"], check=True)
```

For programs that genuinely need a shell pipeline, split into two `subprocess.Popen` calls connected via `stdout=PIPE` / `stdin=PIPE`. Never re-shell user input.

---

## PATCH-003 — Validate path against base directory (PYVULN-036)

**Risk:** SAFE
**Validation:** Replay `?file=../../etc/passwd` — expect 404.

```diff
+ from pathlib import Path
+
  def download(request):
      filename = request.args["file"]
-     path = os.path.join(STATIC_DIR, filename)
-     return send_file(path)
+     base = Path(STATIC_DIR).resolve()
+     candidate = (base / filename).resolve()
+     if not candidate.is_relative_to(base):
+         abort(404)
+     return send_file(candidate)
```

`Path.is_relative_to` was added in Python 3.9; available on every supported version (3.13 / 3.14).

---

## PATCH-004 — Replace `pickle.loads` with safe parser (PYVULN-009)

**Risk:** BREAKING (changes wire format — coordinate with producers).
**Validation:** Send a pickle gadget payload — expect parse error, not RCE.

```diff
- import pickle
- data = pickle.loads(payload)
+ from pydantic import BaseModel, ValidationError
+
+ class Payload(BaseModel):
+     name: str
+     count: int
+     tags: list[str] = []
+
+ try:
+     data = Payload.model_validate_json(payload)
+ except ValidationError as exc:
+     raise BadRequest(str(exc))
```

Migration plan when producers are external:
1. Add new endpoint accepting JSON alongside the existing pickle endpoint.
2. Coordinate cutover with producers.
3. Remove pickle endpoint after producers migrate.

---

## PATCH-005 — `yaml.load` → `yaml.safe_load` (PYVULN-011)

**Risk:** SAFE (refuses arbitrary Python object instantiation; same result for scalar / list / dict YAML).
**Validation:** Send `!!python/object/apply:os.system ["id"]` — expect `yaml.constructor.ConstructorError`.

```diff
- config = yaml.load(payload)
+ config = yaml.safe_load(payload)
```

If `yaml.full_load` appears, replace with `yaml.safe_load` — `full_load` was a half-measure and is still unsafe against carefully crafted payloads.

---

## PATCH-006 — JWT — explicit single-algorithm allowlist (PYVULN-018)

**Risk:** REVIEW (rejects tokens signed with other algorithms — verify all minting paths use the same alg).
**Validation:** Send a token signed with HS256 to a route that expects RS256 — expect 401.

```diff
- payload = jwt.decode(token, public_key, algorithms=["RS256", "HS256"])
+ payload = jwt.decode(
+     token,
+     public_key,
+     algorithms=["RS256"],
+     audience="my-service",
+     issuer="https://auth.example.com",
+     options={"require": ["exp", "iat", "iss", "aud"]},
+ )
```

For `python-jose` users: it is in maintenance mode and lagging on CVEs. Migrate to `pyjwt >= 2.9` or `authlib >= 1.3` in a follow-up patch.

---

## PATCH-007 — Tighten CORS (PYVULN-030)

**Risk:** REVIEW (changes which origins can call the API — confirm allowlist covers every production client).
**Validation:** Send `Origin: https://evil.example` — expect no `Access-Control-Allow-Origin` reflection.

FastAPI:

```diff
  app.add_middleware(
      CORSMiddleware,
-     allow_origins=["*"],
-     allow_credentials=True,
+     allow_origins=settings.allowed_origins,        # explicit list from settings
+     allow_credentials=True,                         # OK now that origins are not "*"
      allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
      allow_headers=["Authorization", "Content-Type"],
      max_age=600,
  )
```

Django (`django-cors-headers`):

```diff
- CORS_ALLOW_ALL_ORIGINS = True
- CORS_ALLOW_CREDENTIALS = True
+ CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS")
+ CORS_ALLOW_CREDENTIALS = True
+ CORS_ALLOW_ALL_ORIGINS = False
```

Flask (`flask-cors`):

```diff
- CORS(app, origins="*", supports_credentials=True)
+ CORS(
+     app,
+     origins=app.config["ALLOWED_ORIGINS"],         # explicit list
+     supports_credentials=True,
+     methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
+     allow_headers=["Authorization", "Content-Type"],
+     max_age=600,
+ )
```

---

## PATCH-008 — Disable Django DEBUG in production (PYVULN-027)

**Risk:** REVIEW (changes error pages — confirm a 500 template exists and `LOGGING` is configured).
**Validation:** Trigger an unhandled exception — expect the generic 500 page, not the Django traceback.

```diff
- DEBUG = True
+ import environ
+ env = environ.Env(DEBUG=(bool, False))
+ environ.Env.read_env()
+
+ DEBUG = env("DEBUG")
+ if DEBUG and env("ENVIRONMENT", default="production") == "production":
+     raise ImproperlyConfigured("DEBUG must be False in production")
+
- ALLOWED_HOSTS = []
+ ALLOWED_HOSTS = env.list("ALLOWED_HOSTS")
+
+ SECRET_KEY = env("DJANGO_SECRET_KEY")             # fail closed if absent
```

Add a `templates/500.html` template and verify `LOGGING` writes to stdout / Sentry.

---

## PATCH-009 — Jinja2 autoescape + sandboxed loader (PYVULN-005)

**Risk:** SAFE (auto-escape is the default in modern Flask; reverting it is the misconfiguration).
**Validation:** Send `{{7*7}}` and `{{config.items()}}` — expect literal output, not evaluation.

```diff
- from jinja2 import Environment
- env = Environment(autoescape=False)
- template = env.from_string(request.args["template"])
- return template.render()
+ from jinja2 import Environment, FileSystemLoader, select_autoescape
+
+ env = Environment(
+     loader=FileSystemLoader("templates/"),
+     autoescape=select_autoescape(["html", "xml"]),
+ )
+ # User input is passed as DATA, never as the template itself
+ template = env.get_template("page.html")
+ return template.render(user_value=request.args["v"])
```

For Flask: `render_template("page.html", user_value=request.args["v"])` is already safe — never `render_template_string(request.args["template"])`.

---

## PATCH-010 — SSRF allowlist (PYVULN-033)

**Risk:** REVIEW (rejects requests to non-allowlisted hosts — confirm the allowlist covers every legitimate upstream).
**Validation:** Send `?url=http://169.254.169.254/latest/meta-data/` — expect 400, not AWS metadata.

```diff
+ from urllib.parse import urlparse
+ import ipaddress
+ import socket
+
+ ALLOWED_HOSTS = {"api.partner.example", "files.partner.example"}
+
+ def safe_fetch(url: str) -> bytes:
+     p = urlparse(url)
+     if p.scheme != "https":
+         raise ValueError("scheme must be https")
+     if p.hostname not in ALLOWED_HOSTS:
+         raise ValueError("host not allowed")
+     ip = socket.gethostbyname(p.hostname)
+     addr = ipaddress.ip_address(ip)
+     if addr.is_private or addr.is_loopback or addr.is_link_local or addr.is_multicast:
+         raise ValueError("ip not allowed")
+     return requests.get(url, timeout=5, allow_redirects=False).content
+
  @router.get("/fetch")
  async def fetch(url: str):
-     return requests.get(url).text
+     return safe_fetch(url)
```

Notes: DNS rebinding bypasses naive allowlists — pin the resolved IP, or use a dedicated egress proxy with allowlisting.

---

## PATCH-011 — `random` → `secrets` (PYVULN-015)

**Risk:** SAFE
**Validation:** Generate 1000 tokens; check entropy with `ent` or histogram in pytest.

```diff
- import random, string
- token = "".join(random.choices(string.ascii_letters + string.digits, k=32))
+ import secrets
+ token = secrets.token_urlsafe(32)
```

For UUIDs used as identifiers (not secrets), `uuid.uuid4()` is fine — it uses `os.urandom`. For session IDs, password reset tokens, CSRF tokens, MFA codes: always `secrets.*`.

---

## PATCH-012 — ZIP slip / `tarfile.extractall` (PYVULN-037)

**Risk:** SAFE
**Validation:** Upload a tarball with `../../etc/cron.d/x` member — expect `ValueError` or extraction filter rejection.

Python 3.12+:

```diff
- tarfile.open(upload).extractall(path=upload_dir)
+ tarfile.open(upload).extractall(path=upload_dir, filter="data")
```

Manual (older Python or `zipfile.ZipFile`):

```diff
+ from pathlib import Path
+
+ base = Path(upload_dir).resolve()
- tarfile.open(upload).extractall(path=upload_dir)
+ with tarfile.open(upload) as tf:
+     for member in tf.getmembers():
+         dest = (base / member.name).resolve()
+         if not dest.is_relative_to(base):
+             raise ValueError(f"unsafe path: {member.name}")
+         if member.issym() or member.islnk():
+             raise ValueError(f"link members not allowed: {member.name}")
+     tf.extractall(path=upload_dir)
```

---

## PATCH-013 — XXE via `lxml` / `xml.etree` (PYVULN-039)

**Risk:** SAFE (refuses entity expansion and DTD loading; legitimate XML payloads remain parseable).
**Validation:** Send a payload with `<!ENTITY xxe SYSTEM "file:///etc/passwd">` and reference `&xxe;` — expect `XMLSyntaxError` or `defusedxml.EntitiesForbidden`.

Option A — `defusedxml` (recommended):

```diff
- from lxml import etree
- tree = etree.fromstring(user_xml)
+ from defusedxml.lxml import fromstring
+ tree = fromstring(user_xml)
```

Option B — restrict `lxml` parser explicitly:

```diff
- from lxml import etree
- tree = etree.fromstring(user_xml)
+ from lxml import etree
+ parser = etree.XMLParser(
+     resolve_entities=False,
+     no_network=True,
+     huge_tree=False,
+     load_dtd=False,
+ )
+ tree = etree.fromstring(user_xml, parser=parser)
```

Add `defusedxml` to `requirements.txt` if you choose Option A. `defusedxml` patches stdlib modules to refuse entity expansion and DTD loading by default, which is the safest baseline for any module that touches XML.

---

## Apply sequence (executed by Phase 6 of the lifecycle)

```bash
# 1. For each confirmed patch, in severity order, apply via Edit (never bulk Write)
# 2. Reinstall / sync
uv sync                                # or: pip install -e .
# 3. Type check
mypy --strict src/
# 4. Tests
pytest -q
# 5. Re-run automated audit
pip-audit --strict
bandit -r src/ -q
semgrep --config p/python --config p/owasp-top-ten src/
osv-scanner --lockfile=uv.lock
# 6. Replay payload for the specific finding
```

If any step fails:

```bash
git restore <file>
# re-emit the patch as "manual review required"
```

The skill must report any patch that introduced new findings or test failures and offer to revert.
