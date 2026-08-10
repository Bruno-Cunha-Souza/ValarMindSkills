---
name: mcp-builder
description: "Build MCP servers — research, implement, test, evaluate. Rust (rmcp, default), TypeScript, or Python. Tool design, strict schemas, pagination, actionable errors, spec 2026-07-28 transports, plus a 10-question evaluation that scores the result. Triggers: 'criar servidor MCP', 'expor essa API como MCP', 'build an MCP server', 'wrap this API as MCP tools', '/mcp-builder'. Not for configuring existing MCP servers."
source: https://github.com/anthropics/skills/tree/main/skills/mcp-builder
---

# MCP Builder

## When to Use

- Building a new MCP server that exposes an external API or service as tools.
- Adding tools to an existing MCP server, or reworking a tool surface agents keep misusing.
- Choosing between comprehensive API coverage and workflow tools for a server design.
- Evaluating whether an MCP server actually enables the tasks it was built for.

## Do not use when

- Installing, configuring, or connecting to an **existing** MCP server — that is client setup.
- Auditing a server for vulnerabilities — use `@code-security-review`, which covers confused-deputy and token-passthrough patterns.
- Writing a plain API client with no MCP surface.

## Prerequisites

| Input | Required | How to obtain |
| --- | --- | --- |
| Target API | Yes | User names the service; fetch its docs in Phase 1 |
| Authentication method | Yes | API key, OAuth 2.1, or none — determines Phase 2 client design |
| Language | No | Defaults to Rust; see the Phase 0 table |
| Transport | No | Defaults to stdio for local servers, streamable HTTP for remote |
| Credentials for evaluation | No | Needed only to run Phase 4 against a live service |

Quality here is measured by one thing: whether an LLM can accomplish real tasks with the server. Every rule below serves that.

## Phase 0 — Scope and language

**Inventory the API.** List the endpoints worth exposing, most common operations first. Note auth, rate limits, and pagination style.

**Coverage beats cleverness.** Balance comprehensive endpoint coverage against specialized workflow tools. Workflow tools are convenient for the tasks you predicted; broad coverage lets the agent compose the ones you did not. Performance varies by client — some do better composing basic tools through code execution, others with higher-level workflows. **When uncertain, prioritize comprehensive API coverage.**

**Pick the language:**

| Language | Pick it when | Guide |
| --- | --- | --- |
| **Rust (`rmcp`)** | **Default.** Single static binary, no runtime on the host, strict types, spec `2026-07-28` native | [references/RUST.md](references/RUST.md) |
| TypeScript (`@modelcontextprotocol/sdk`) | MCPB packaging or `npx` distribution is required; largest client ecosystem | [references/TYPESCRIPT.md](references/TYPESCRIPT.md) |
| Python (FastMCP) | The target API already ships a Python SDK worth wrapping, or the surrounding codebase is Python | [references/PYTHON.md](references/PYTHON.md) |

## Phase 1 — Research

**The protocol.** Current revision is `2026-07-28`. Start from the sitemap at `https://modelcontextprotocol.io/sitemap.xml` and fetch pages with a `.md` suffix for markdown. Read the transport and tool-definition pages before designing anything.

**The SDK — fetch live docs, do not work from memory.** Use Context7:

| SDK | Context7 ID |
| --- | --- |
| Rust `rmcp` (official) | `/websites/rs_rmcp_rmcp` |
| TypeScript | `/modelcontextprotocol/typescript-sdk` |
| Python | `/websites/py_sdk_modelcontextprotocol_io_v2` |
| Protocol spec | `/modelcontextprotocol/modelcontextprotocol` |

`rust-mcp-sdk` and other `rmcp`-adjacent names in search results are third-party projects, not the official SDK. The official one is `modelcontextprotocol/rust-sdk`.

**The target API.** Read its documentation: endpoints, authentication, data models, rate limits. Web search and fetch as needed.

**Choose the transport.** stdio for local servers, streamable HTTP for remote. The `2026-07-28` revision removed protocol-level sessions and resumable SSE streams — stateless JSON is the shape. Full rules in [references/BEST_PRACTICES.md](references/BEST_PRACTICES.md).

## Phase 2 — Implement

Follow the language guide for project layout and SDK specifics. The decisions below are the same in all three.

### Naming

| What | Convention |
| --- | --- |
| Server, Rust and TypeScript | `{service}-mcp-server` |
| Server, Python | `{service}_mcp` |
| Tools, all languages | `snake_case`, service-prefixed, action verb first — `github_create_issue`, `slack_send_message` |

Prefixes are not decoration: several servers load into one client, and `send_message` collides.

### Tool descriptions

The description is the agent's only view of the tool. Each one states what the tool does and does not do, every parameter, the return schema, two or three use/don't-use examples, and the error strings the agent should expect. Descriptions must **precisely match actual functionality** — one that overpromises is worse than a missing tool, because the agent picks it and fails.

### Annotations

Set all four on every tool.

| Annotation | Default | Meaning |
| --- | --- | --- |
| `readOnlyHint` | `false` | Does not modify its environment |
| `destructiveHint` | `true` | Performs destructive updates |
| `idempotentHint` | `false` | Repeated calls add no further effect |
| `openWorldHint` | `true` | Interacts with external entities |

Omitting them declares a destructive, non-idempotent, open-world tool. **They are hints, not security guarantees** — enforce read-only-ness in the implementation, never in the metadata.

### Schemas

Validate every input with the language's schema library — `schemars` (Rust), Zod (TypeScript), Pydantic (Python) — in strict mode, so a misspelled parameter fails loudly instead of being silently dropped. Declare an output schema wherever the tool returns structured data, and return both surfaces: text for the agent to read, structured content for the client to process.

### Pagination

Every list tool respects `limit` (default 20–50), paginates by offset or cursor, and returns:

```json
{ "total": 150, "count": 20, "offset": 0, "items": [], "has_more": true, "next_offset": 20 }
```

Never load the full result set into memory. Truncate oversized responses against a character limit with a message telling the agent how to narrow the query — silently flooding its context is the failure this prevents.

### Errors

Tool failures go **inside the result** (`isError` / an error result), never as a protocol error. A protocol error kills the call; a result error lets the agent read it and adapt. Every message names a next step and leaks nothing internal.

```
Bad:   "Error: request failed"
Bad:   "Error: HTTPError 429 at /internal/svc/rates.py:88"
Good:  "Error: rate limit exceeded. Retry after 30s, or narrow the query with filter='active_only'."
```

### Security

- Secrets from environment variables only, validated at startup.
- Sanitize file paths against traversal; validate URLs and external identifiers; never interpolate arguments into a shell command.
- OAuth 2.1: validate tokens before processing, and accept only tokens minted for your server. A token issued for another audience that your server honours is the confused-deputy hole.
- Streamable HTTP served locally: validate the `Origin` header, bind to `127.0.0.1` not `0.0.0.0`, enable DNS rebinding protection.
- **stdio writes nothing to stdout but protocol frames.** Logging goes to stderr. One stray `println!`/`console.log`/`print` desynchronizes the stream and the client dies on a parse error that names nothing.

## Phase 3 — Review and test

Review for duplicated request/format code, inconsistent error handling, incomplete type coverage, and vague tool descriptions. Then build and inspect:

```bash
# Rust
cargo build --release && cargo clippy --all-targets --all-features -- -D warnings
npx @modelcontextprotocol/inspector cargo run

# TypeScript
npm run build && node dist/index.js --help
npx @modelcontextprotocol/inspector node dist/index.js

# Python
python -m py_compile src/<service>_mcp/server.py
npx @modelcontextprotocol/inspector uv run python -m <service>_mcp

# Any language, server already running over HTTP
mcp-inspector --server-url http://127.0.0.1:8000/mcp --transport http \
  --header "Authorization: Bearer $TOKEN"
```

Confirm in the Inspector that every tool appears with the annotations you set. Work the language guide's quality checklist before moving on.

## Phase 4 — Evaluate

The only phase that measures whether the server does its job. Full rules, examples, and the good/poor question catalog: [references/EVALUATION.md](references/EVALUATION.md).

1. **Inspect the tools** — schemas and descriptions only, calling nothing, reading no source code.
2. **Explore the data** with read-only, non-destructive calls until you find content concrete enough to build questions around.
3. **Write 10 questions**: independent, read-only, multi-hop, realistic, stable over time, each with a single answer verifiable by string comparison. No keywords copied from the target content.
4. **Solve each one yourself** to establish the answer key; drop any that turned out to need a write.
5. **Write `evaluation.xml`:**

```xml
<evaluation>
  <qa_pair>
    <question>...</question>
    <answer>3</answer>
  </qa_pair>
</evaluation>
```

6. **Run it** — answer all 10 using only the server's tools, without consulting the answer key, then compare.

Acceptance is 8 of 10. Report the score **and the cause of every miss**: which tool was not found, which description misled, which response was truncated. A score without diagnosis is a number; a score with causes is the Phase 2 fix list.

## Constraints

- **Never** log to stdout on the stdio transport.
- **Never** return a tool failure as a protocol error when it can go in the result object.
- **Never** put secrets in code or committed config — environment variables only.
- **Never** adopt the deprecated HTTP+SSE transport (`2024-11-05`) in a new server.
- **Never** treat annotations as a security boundary.
- **Never** read the server's source code while generating evaluations — it contaminates the measurement.
- **Never** use a write or destructive operation to answer an evaluation question.
- **Must** set all four annotations on every tool.
- **Must** validate every input with a strict schema at the trust boundary.
- **Must** implement pagination on every list-returning tool.
- **Must** name tools `snake_case` with a service prefix.
- **Must** make every error message actionable and free of internal detail.

## Output format

Deliver, in this order:

1. **Tool inventory** — one line per tool: name, what it does, annotations.
2. **The server** — source, following the language guide's layout.
3. **Build proof** — the actual command output showing a clean build and lint.
4. **`evaluation.xml`** — the 10 verified question/answer pairs.
5. **Evaluation result** — score out of 10, and for each miss the specific cause.
6. **Gaps** — endpoints deliberately not exposed, and why.

## Example request

- "Criar um servidor MCP para a API do Linear"
- "Build an MCP server that exposes our internal orders API"
- "Expor essa API como tools MCP, em Rust"
- "Add a search tool to my existing MCP server and re-run the evaluation"
- "/mcp-builder"

## Related Skills

- `@code-security-review` — audits an MCP server for vulnerabilities; this skill builds one.
- `@prompt-engineering` — a tool description is a prompt; use it to harden vague ones.
- `@clean-code` / `@code-review` — code quality after Phase 2.
- `@ci-cd-generator` — pipeline for the new server.
- `@github-commit` — commit conventions.

## References

- [BEST_PRACTICES](references/BEST_PRACTICES.md) — language-agnostic rules: naming, annotations, pagination, transports, security, errors
- [RUST](references/RUST.md) — `rmcp` implementation guide (default language) + quality checklist
- [TYPESCRIPT](references/TYPESCRIPT.md) — `@modelcontextprotocol/sdk` implementation guide + quality checklist
- [PYTHON](references/PYTHON.md) — FastMCP implementation guide + quality checklist
- [EVALUATION](references/EVALUATION.md) — Phase 4 in full: question rules, process, examples, scoring

## Attribution

Based on [anthropics/skills/skills/mcp-builder](https://github.com/anthropics/skills/tree/main/skills/mcp-builder) (Apache 2.0 license). This skill ports the four-phase lifecycle, the MCP best-practices catalog, the language implementation guides, and the evaluation methodology to the ValarMindSkills format.

Three deliberate departures from upstream. **Rust is added and made the default** — upstream covers only Python and TypeScript and recommends TypeScript; `rmcp` reaches the same tool surface with a single static binary, and `references/RUST.md` has no upstream equivalent. **The Python evaluation harness (`scripts/evaluation.py`, `connections.py`) was not ported** — `scripts/` inside a skill is an anti-pattern in this repository, and the harness would add a Python dependency plus an `ANTHROPIC_API_KEY` to run a loop the invoking agent already performs; Phase 4 runs through the agent instead. **Transport guidance was rewritten for protocol revision `2026-07-28`**, which removed protocol-level sessions and resumable SSE streams; upstream's guides still describe stateful sessions and the deprecated HTTP+SSE transport.
