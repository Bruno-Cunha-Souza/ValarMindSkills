# RUST — mcp-builder

> Reference companion for the [mcp-builder](../SKILL.md) skill. Implementation guide for the default language. Language-agnostic rules live in [BEST_PRACTICES.md](BEST_PRACTICES.md).

Official SDK: [`rmcp`](https://github.com/modelcontextprotocol/rust-sdk). Live docs via Context7 `/websites/rs_rmcp_rmcp`. Beware of look-alikes on crates.io and in search results — `rust-mcp-sdk` and other `rmcp`-adjacent crates are third-party projects, not the official SDK.

`rmcp` implements the stable `2026-07-28` specification and stays compatible with `2025-11-25` and earlier.

## Why Rust is the default here

A single static binary with no runtime to install on the host, strict types that make an invalid tool response a compile error, and native support for the current spec revision. The trade is compile time and a smaller pool of MCP examples to copy from. Pick TypeScript when MCPB packaging or `npx` distribution is a requirement; pick Python when the target API already ships a Python SDK worth wrapping.

## Setup

```sh
cargo new --bin acme-mcp-server
cd acme-mcp-server
cargo add rmcp --features server,transport-io
cargo add tokio --features rt-multi-thread,macros
cargo add serde --features derive
cargo add schemars serde_json anyhow thiserror
cargo add tracing tracing-subscriber
```

Crate and binary are named `{service}-mcp-server`.

## Project structure

```text
acme-mcp-server/
├── Cargo.toml
├── README.md
└── src/
    ├── main.rs          # transport bootstrap only
    ├── server.rs        # the handler struct, #[tool_router], #[tool_handler]
    ├── client.rs        # HTTP client, auth, retry
    ├── schemas.rs       # Deserialize + JsonSchema input types
    ├── format.rs        # markdown/json rendering, pagination envelope, truncation
    └── error.rs         # error type + conversion to CallToolResult
```

Small servers may collapse `server.rs` into `main.rs`. Split `tools/` by domain once one file passes ~400 lines.

## Input schemas

Derive `Deserialize` and `JsonSchema`; the tool's input schema is generated from the type. `schemars` emits JSON Schema 2020-12. Constraints and descriptions belong on the fields — they are what the agent reads.

```rust
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SearchUsers {
    /// Search string matched against names and emails, e.g. "team:marketing".
    pub query: String,

    /// Maximum results to return, 1-100.
    #[schemars(range(min = 1, max = 100))]
    #[serde(default = "default_limit")]
    pub limit: u32,

    /// Number of results to skip, for pagination.
    #[serde(default)]
    pub offset: u32,

    #[serde(default)]
    pub response_format: ResponseFormat,
}

#[derive(Debug, Default, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum ResponseFormat {
    #[default]
    Markdown,
    Json,
}

fn default_limit() -> u32 { 20 }
```

`#[serde(deny_unknown_fields)]` is the Rust equivalent of Zod's `.strict()` — an agent passing a misspelled parameter gets a validation error instead of a silently ignored field.

## Registering tools

`#[tool_router]` on the `impl` block collects the tools; `#[tool_handler]` on the `ServerHandler` impl generates `call_tool`, `list_tools`, `get_tool`, and `get_info`.

```rust
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::{CallToolResult, ErrorData, ToolAnnotations};
use rmcp::{tool, tool_handler, tool_router, ServerHandler};

#[derive(Clone)]
pub struct AcmeServer {
    client: ApiClient,
}

#[tool_router]
impl AcmeServer {
    #[tool(
        description = "Search Acme users by name, email, or team. Searches existing \
                       profiles only; does not create or modify users.\n\
                       \n\
                       Returns: total, count, offset, users[{id,name,email,team,active}], \
                       has_more, next_offset.\n\
                       \n\
                       Use when: \"find all marketing team members\" -> query=\"team:marketing\".\n\
                       Do not use when: you need to create a user (use acme_create_user).\n\
                       \n\
                       Errors: \"Error: rate limit exceeded\" on 429; \
                       \"No users found matching '<query>'\" when the search is empty.",
        annotations = ToolAnnotations::from_raw(
            Some("Search Acme Users".into()),
            Some(true),   // read_only_hint
            Some(false),  // destructive_hint
            Some(true),   // idempotent_hint
            Some(true),   // open_world_hint
        )
    )]
    pub async fn acme_search_users(
        &self,
        Parameters(params): Parameters<SearchUsers>,
    ) -> Result<CallToolResult, ErrorData> {
        let page = match self.client.search_users(&params).await {
            Ok(page) => page,
            Err(e) => return Ok(to_tool_error(e)),
        };

        if page.items.is_empty() {
            return Ok(CallToolResult::success(vec![
                format!("No users found matching '{}'", params.query).into(),
            ]));
        }

        let envelope = paginate(&page, params.offset);
        let text = match params.response_format {
            ResponseFormat::Markdown => render_users_md(&page),
            ResponseFormat::Json => serde_json::to_string_pretty(&envelope)?,
        };

        // Text for the agent to read, structure for the client to process.
        let mut result = CallToolResult::success(vec![text.into()]);
        result.structured_content = Some(serde_json::to_value(&envelope)?);
        Ok(result)
    }
}

#[tool_handler(
    name = "acme-mcp-server",
    instructions = "Read and search Acme users, projects, and audit events."
)]
impl ServerHandler for AcmeServer {}
```

`name` and `version` default to `CARGO_CRATE_NAME` and `CARGO_PKG_VERSION`. Implementing `get_info()` yourself suppresses the generated one:

```rust
#[tool_handler]
impl ServerHandler for AcmeServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo::new(ServerCapabilities::builder().enable_tools().build())
    }
}
```

`ToolAnnotations` also exposes chainable setters — `.read_only(bool)`, `.destructive(bool)`, `.idempotent(bool)`, `.open_world(bool)` — if you prefer building them a field at a time.

## Output schemas and structured content

Declare an output schema wherever the tool returns structured data. `ToolBase::output_schema()` derives it from `Self::Output` by default; override it to return `None` for tools with no structured output, or set a hand-written one with `Tool::with_raw_output_schema`.

`CallToolResult` has four constructors — `success(Vec<ContentBlock>)`, `error(Vec<ContentBlock>)`, `structured(Value)`, `structured_error(Value)` — and a public `structured_content: Option<Value>` field for carrying both surfaces at once, as in the tool above.

```rust
CallToolResult::structured(serde_json::json!({
    "total": 150,
    "count": 20,
    "offset": 0,
    "items": items,
    "has_more": true,
    "next_offset": 20
}))
```

## Errors

The split is load-bearing:

- **`Ok(CallToolResult::error(...))`** — the tool ran and failed. The agent sees the message and can adapt. This is where nearly every failure belongs: 404, 403, 429, timeout, empty result, invalid combination of arguments.
- **`Err(ErrorData)`** — protocol-level failure. Kills the call. Reserve it for genuinely broken requests.

```rust
pub fn to_tool_error(e: ApiError) -> CallToolResult {
    let msg = match e {
        ApiError::Status(404) => "Error: resource not found. Check the ID.".to_string(),
        ApiError::Status(403) => "Error: permission denied for this resource.".to_string(),
        ApiError::Status(429) => {
            "Error: rate limit exceeded. Retry after 30s, or narrow the query with \
             filter='active_only'."
                .to_string()
        }
        ApiError::Timeout => "Error: request timed out. Retry with a smaller limit.".to_string(),
        // Internal detail stays internal — log it, do not return it.
        other => {
            tracing::error!(error = ?other, "unhandled api error");
            "Error: upstream request failed.".to_string()
        }
    };
    CallToolResult::error(vec![msg.into()])
}
```

Every arm names a next step. None of them leak a URL, a query, or a stack trace.

## Transports

Enable by feature flag:

| Transport | Feature | Use |
| :--- | :--- | :--- |
| stdio | `transport-io` | Local server, client subprocess |
| Streamable HTTP (server) | `transport-streamable-http-server` | Remote server, mounted as a tower service |
| Child process | `transport-child-process` | Client side, spawning a server |
| Streamable HTTP (client) | `transport-streamable-http-client-reqwest` | Client side |
| Worker | `transport-worker` | In-process, tests |

### stdio

```rust
use rmcp::{transport::stdio, ServiceExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // stdout is the protocol channel. Logs go to stderr or they corrupt the stream.
    tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let service = AcmeServer::new(ApiClient::from_env()?).serve(stdio()).await?;
    service.waiting().await?;
    Ok(())
}
```

The stderr rule is not style. A single `println!` reaching stdout desynchronizes the JSON-RPC stream and the client dies on a parse error that names nothing useful.

### Streamable HTTP

`StreamableHttpService` is a tower service; mount it on axum or anything else tower-compatible. Match the `2026-07-28` shape — stateless, JSON responses:

```rust
use rmcp::transport::streamable_http_server::StreamableHttpServerConfig;

let config = StreamableHttpServerConfig::default()
    .with_stateful_mode(false)      // no protocol sessions
    .with_json_response(true)       // bypass SSE framing
    .with_allowed_hosts(["127.0.0.1:8000"])
    .with_allowed_origins(["https://app.example.com"]);
```

`with_allowed_hosts` and `with_allowed_origins` are the DNS-rebinding protection from [BEST_PRACTICES.md](BEST_PRACTICES.md). `disable_allowed_hosts` / `disable_allowed_origins` exist and are not for public deployments. Bind to `127.0.0.1`, not `0.0.0.0`.

For a fully sessionless server, pair the config with `NeverSessionManager` instead of the default `LocalSessionManager`.

## Build and test

```sh
cargo build --release
cargo clippy --all-targets --all-features -- -D warnings
cargo test
npx @modelcontextprotocol/inspector cargo run
# or against a running HTTP server:
mcp-inspector --server-url http://127.0.0.1:8000/mcp --transport http \
  --header "Authorization: Bearer $TOKEN"
```

Deeper Rust tooling (`cargo audit`, `cargo deny`, `cargo machete`, `miri`) is catalogued in `@code-review` under `references/RUST.md`.

## Quality checklist

**Strategic design**

- [ ] Tools cover the API surface an agent needs, not just the endpoints that were easy
- [ ] Tool names are `snake_case` with a service prefix
- [ ] Response format optimizes for agent context — markdown default, json on request
- [ ] Human-readable identifiers surfaced alongside opaque IDs
- [ ] Error messages point at the next action

**Implementation**

- [ ] Every tool carries a description with args, return schema, use/don't-use examples, and error strings
- [ ] Every tool sets all four annotations
- [ ] Every input type derives `JsonSchema` and uses `#[serde(deny_unknown_fields)]`
- [ ] Field-level constraints and doc comments present on every input field
- [ ] `output_schema` declared wherever structured data is returned
- [ ] Structured content returned alongside text

**Rust quality**

- [ ] No `unwrap()`/`expect()` on any path reachable from a tool call
- [ ] `Result<CallToolResult, ErrorData>` on every tool; failures return `Ok(CallToolResult::error(..))`
- [ ] Errors modelled with `thiserror`; internal detail logged, never returned
- [ ] All I/O is `async`; no blocking calls inside the runtime
- [ ] `cargo clippy -- -D warnings` clean

**Configuration**

- [ ] Crate and binary named `{service}-mcp-server`
- [ ] Secrets read from environment, validated at startup
- [ ] Only the needed transport features enabled in `Cargo.toml`
- [ ] Streamable HTTP: stateless + JSON, allowed hosts and origins set, bound to `127.0.0.1`

**Code quality**

- [ ] Pagination implemented on every list tool, default limit 20–50
- [ ] Large responses truncate against a `CHARACTER_LIMIT` constant with an explicit message
- [ ] Filtering offered for potentially large result sets
- [ ] Timeouts and connection errors handled on every network call
- [ ] Shared logic extracted; no duplicated request/format code per tool

**Build**

- [ ] `cargo build --release` succeeds
- [ ] Binary starts and serves over the configured transport
- [ ] Inspector lists every tool with the correct annotations
- [ ] Sample calls return the expected shape
- [ ] stdio path writes nothing to stdout except protocol frames
