# BEST_PRACTICES — mcp-builder

> Reference companion for the [mcp-builder](../SKILL.md) skill. Language-agnostic rules that apply to every MCP server regardless of SDK. Language specifics live in [RUST.md](RUST.md), [TYPESCRIPT.md](TYPESCRIPT.md), [PYTHON.md](PYTHON.md).

## Server naming

| Language | Format | Examples |
| :--- | :--- | :--- |
| Rust | `{service}-mcp-server` (crate and binary, kebab-case) | `slack-mcp-server`, `github-mcp-server` |
| TypeScript | `{service}-mcp-server` (package name, kebab-case) | `slack-mcp-server`, `jira-mcp-server` |
| Python | `{service}_mcp` (module, snake_case) | `slack_mcp`, `github_mcp` |

Names are general, descriptive, inferable from task context, and carry no version number. The name an agent sees is the one it reasons about when picking a server.

## Tool naming

1. **`snake_case` for every tool identifier** — `search_users`, `create_project`, `get_channel_info`. Same across all three languages; this is protocol surface, not host-language style.
2. **Prefix with the service.** Multiple servers load into one client and collide otherwise. `slack_send_message`, not `send_message`. `github_create_issue`, not `create_issue`.
3. **Start with an action verb** — `get`, `list`, `search`, `create`, `update`, `delete`.
4. **Be specific.** Generic names lose the disambiguation race against every other loaded server.

## Tool design

- Descriptions narrowly and unambiguously describe what the tool does, and **precisely match actual behaviour**. A description that overpromises is worse than a missing tool: the agent picks it and fails.
- One tool, one operation. Keep them atomic.
- Always supply the four annotations (below).
- Prefer comprehensive API coverage over a small set of clever workflow tools. Agents compose; guessing which workflows matter usually guesses wrong. When genuinely uncertain, cover the API.

## Tool annotations

| Annotation | Type | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `readOnlyHint` | boolean | `false` | Tool does not modify its environment |
| `destructiveHint` | boolean | `true` | Tool performs destructive updates |
| `idempotentHint` | boolean | `false` | Repeated calls with the same args add no further effect |
| `openWorldHint` | boolean | `true` | Tool interacts with external entities |

Note the defaults: omitting annotations declares a destructive, non-idempotent, open-world tool. That is the safe default, and it is also wrong for most read tools — set them explicitly.

**Annotations are hints, not security guarantees. Clients must not make security-critical decisions based solely on annotations.** Enforce read-only-ness in the implementation, not in the metadata.

## Response formats

Offer both, default to markdown.

**`response_format="markdown"`** — human-readable. Headers and lists, timestamps converted to readable form, display names with IDs in parentheses, verbose metadata omitted.

**`response_format="json"`** — machine-readable. All available fields, consistent field names and types.

Modern SDKs also carry structured data alongside the text: `structuredContent` (TypeScript), `CallToolResult::structured` (Rust), structured output types (Python). Return both when the SDK supports it — text for the agent to read, structure for the client to process.

## Pagination

Every list-returning tool:

- Respects `limit`. Default it to 20–50.
- Paginates by offset or cursor.
- Returns `has_more`, `next_offset`/`next_cursor`, and `total_count`.
- Never loads the full result set into memory.

```json
{
  "total": 150,
  "count": 20,
  "offset": 0,
  "items": [],
  "has_more": true,
  "next_offset": 20
}
```

Pair this with a character limit: large responses truncate with an explicit message telling the agent how to narrow the query, rather than silently flooding its context.

## Transports

Protocol revision **2026-07-28** is current.

### stdio

Local integrations and command-line tools. Runs as a subprocess of the client, minimal configuration.

**Never write to stdout.** stdout *is* the protocol channel; a stray `println!`/`console.log`/`print` corrupts the stream and the connection dies with a confusing parse error. All logging goes to stderr.

### Streamable HTTP

Remote servers, web services, multiple simultaneous clients.

The **2026-07-28** revision removed protocol-level sessions and resumable SSE streams. A server supporting only this revision:

- responds `405 Method Not Allowed` to HTTP `GET` and `DELETE` on the MCP endpoint;
- ignores an incoming `Mcp-Session-Id` header, and neither mints nor echoes session IDs;
- ignores `Last-Event-ID` — streams are not resumable.

This makes stateless JSON the only shape, which is also the easiest to scale: no session affinity, no sticky routing.

### HTTP+SSE (2024-11-05) — deprecated

Do not adopt it in new implementations. Servers that must serve old clients host both the legacy SSE/POST endpoints and the current MCP endpoint; clients POST first and fall back to the SSE stream on `400`/`404`/`405`.

### Choosing

| Factor | stdio | Streamable HTTP |
| :--- | :--- | :--- |
| Deployment | Local | Remote |
| Clients | Single | Multiple |
| Setup cost | Low | Medium |
| Server-initiated messages | No | Yes |

## Security

### Authentication

**OAuth 2.1** — certificates from recognized authorities. Validate access tokens before processing any request, and accept only tokens minted for your server. A token issued for another audience that your server honours is the confused-deputy hole.

**API keys** — environment variables only, never in code or config committed to a repo. Validate on startup so failure is loud and immediate rather than surfacing as a mystery 401 mid-task. Authentication failure messages state what is missing, not what the key was.

### Input validation

Schema-validate every input — `schemars` (Rust), Zod (TypeScript), Pydantic (Python). Then, beyond the schema:

- Sanitize file paths against directory traversal.
- Validate URLs and externally supplied identifiers.
- Bound parameter sizes and ranges.
- Never interpolate arguments into a shell command.

### DNS rebinding

Streamable HTTP servers bound to localhost are reachable from any web page the user visits unless protected:

- Validate the `Origin` header on every incoming connection.
- Bind to `127.0.0.1`, not `0.0.0.0`.
- Enable DNS rebinding protection.

### Error hygiene

Internal errors stay internal. Log security-relevant detail server-side; return a message that helps the agent without revealing stack traces, queries, or paths. Clean up resources on every error path.

## Error handling

- Report tool failures **inside the result object** (`isError` / an error `CallToolResult`), not as JSON-RPC protocol errors. A protocol error kills the call; a result error lets the agent read it and adapt.
- Use standard JSON-RPC error codes for genuine protocol-level failures only.
- Every message names a next step.

```
Bad:   "Error: request failed"
Bad:   "Error: HTTPError 429 at /internal/svc/rates.py:88"
Good:  "Error: rate limit exceeded. Retry after 30s, or narrow the query with filter='active_only'."
```

## Testing

- **Functional** — valid and invalid inputs on every tool.
- **Integration** — real interaction with the external system.
- **Security** — authentication, input sanitization, rate limiting.
- **Performance** — behaviour under load and at timeout boundaries.
- **Error paths** — correct reporting and resource cleanup.

## Documentation

- Every tool and capability documented.
- At least three worked examples per major feature.
- Security considerations stated.
- Required permissions and access levels listed.
- Rate limits and performance characteristics documented.
