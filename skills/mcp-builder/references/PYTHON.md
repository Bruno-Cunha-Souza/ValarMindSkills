# PYTHON — mcp-builder

> Reference companion for the [mcp-builder](../SKILL.md) skill. Language-agnostic rules live in [BEST_PRACTICES.md](BEST_PRACTICES.md).

Official SDK: [`mcp`](https://github.com/modelcontextprotocol/python-sdk), whose server layer is FastMCP. Live docs via Context7 `/websites/py_sdk_modelcontextprotocol_io_v2` or `/modelcontextprotocol/python-sdk`.

**Pick Python when** the target API already ships a Python SDK worth wrapping, or the server lives inside a data/ML codebase that is Python anyway. Otherwise the default is [Rust](RUST.md).

## Setup

```sh
uv init acme-mcp && cd acme-mcp
uv add mcp pydantic httpx
```

Module is named `{service}_mcp` — snake_case, no version number.

## Project structure

A single-file server is fine to start. Split once it grows:

```text
acme_mcp/
├── pyproject.toml
├── README.md
└── src/acme_mcp/
    ├── __main__.py       # transport bootstrap
    ├── server.py         # FastMCP instance and tool registration
    ├── client.py         # HTTP client, auth, retry
    ├── schemas.py        # Pydantic input models
    └── format.py         # markdown/json rendering, pagination, truncation
```

## Server initialization

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("acme_mcp")

# ... tool definitions ...

if __name__ == "__main__":
    mcp.run()
```

Under stdio, stdout is the protocol channel. Configure logging to stderr and never `print()` — one stray write desynchronizes the JSON-RPC stream.

## Input schemas

Pydantic v2 models with `extra="forbid"` — the equivalent of Zod's `.strict()`. Field descriptions and constraints are what the agent reads.

```python
from typing import List, Literal, Optional
from pydantic import BaseModel, ConfigDict, Field


class UserSearchInput(BaseModel):
    """Input model for the user search tool."""

    model_config = ConfigDict(
        str_strip_whitespace=True,
        validate_assignment=True,
        extra="forbid",
    )

    query: str = Field(
        ...,
        description="Search string matched against names and emails (e.g. 'team:marketing')",
        min_length=1,
        max_length=100,
    )
    limit: int = Field(default=20, description="Maximum results to return", ge=1, le=100)
    offset: int = Field(default=0, description="Number of results to skip, for pagination", ge=0)
    response_format: Literal["markdown", "json"] = Field(default="markdown")
```

Pydantic does the validation. Do not hand-roll checks the model already enforces.

## Registering tools

`@mcp.tool` with an explicit `name` and all four annotations. The docstring becomes the tool description — it carries args, the full return schema, use/don't-use examples, and the error strings the agent should expect.

```python
@mcp.tool(
    name="acme_search_users",
    annotations={
        "title": "Search Acme Users",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True,
    },
)
async def acme_search_users(params: UserSearchInput) -> str:
    """Search for users in Acme by name, email, or team.

    Searches existing user profiles, supporting partial matches and filters.
    Does NOT create or modify users.

    Args:
        params (UserSearchInput):
            - query (str): Search string matched against names/emails
            - limit (int): Maximum results, 1-100 (default: 20)
            - offset (int): Results to skip for pagination (default: 0)
            - response_format ('markdown' | 'json'): Output format (default: 'markdown')

    Returns:
        str: For json format, an object with schema:
            {
              "total": int, "count": int, "offset": int,
              "users": [{"id": str, "name": str, "email": str,
                         "team": str, "active": bool}],
              "has_more": bool, "next_offset": int | None
            }

    Examples:
        - "Find all marketing team members" -> query="team:marketing"
        - Don't use when: you need to create a user (use acme_create_user)

    Errors:
        - "Error: rate limit exceeded" on 429
        - "No users found matching '<query>'" when the search is empty
    """
    try:
        data = await api_request("users/search", q=params.query,
                                 limit=params.limit, offset=params.offset)
    except Exception as e:
        return _handle_api_error(e)

    users = data.get("users", [])
    if not users:
        return f"No users found matching '{params.query}'"

    total = data.get("total", 0)
    has_more = total > params.offset + len(users)
    envelope = {
        "total": total,
        "count": len(users),
        "offset": params.offset,
        "users": users,
        "has_more": has_more,
        "next_offset": params.offset + len(users) if has_more else None,
    }

    if params.response_format == "markdown":
        return render_users_markdown(params.query, total, users)
    return json.dumps(envelope, indent=2)
```

FastMCP also supports structured output types (TypedDict, Pydantic models) as return annotations — use them when the client benefits from a machine-readable surface alongside the text.

## Errors

One helper, consistent across every tool. Each message names a next step and leaks nothing internal.

```python
def _handle_api_error(e: Exception) -> str:
    """Consistent error formatting across all tools."""
    if isinstance(e, httpx.HTTPStatusError):
        status = e.response.status_code
        if status == 404:
            return "Error: resource not found. Check the ID."
        if status == 403:
            return "Error: permission denied for this resource."
        if status == 429:
            return ("Error: rate limit exceeded. Retry after 30s, or narrow the query "
                    "with filter='active_only'.")
        logger.error("api error %s", status)
        return "Error: upstream request failed."
    if isinstance(e, httpx.TimeoutException):
        return "Error: request timed out. Retry with a smaller limit."
    logger.exception("unhandled api error")
    return "Error: upstream request failed."
```

## Advanced FastMCP features

Reach for these only when the server needs them:

- **Context injection** — logging, progress reporting, elicitation.
- **Resource registration** — for data endpoints that are read, not called.
- **Lifespan management** — persistent connections opened once at startup.
- **Structured output types** — TypedDict or Pydantic return annotations.

## Transports

`mcp.run()` defaults to stdio. For streamable HTTP, match the `2026-07-28` shape: stateless, JSON responses, no session IDs minted or echoed, `405` on `GET`/`DELETE` at the MCP endpoint. Validate the `Origin` header and bind to `127.0.0.1` when serving locally. See [BEST_PRACTICES.md](BEST_PRACTICES.md#transports).

## Build and test

```sh
python -m py_compile src/acme_mcp/server.py
uv run python -m acme_mcp --help
npx @modelcontextprotocol/inspector uv run python -m acme_mcp
# or against a running HTTP server:
mcp-inspector --server-url http://127.0.0.1:8000/mcp --transport http \
  --header "Authorization: Bearer $TOKEN"
```

## Quality checklist

**Strategic design**

- [ ] Tools cover the API surface an agent needs, not just the endpoints that were easy
- [ ] Tool names are `snake_case` with a service prefix
- [ ] Response format optimizes for agent context — markdown default, json on request
- [ ] Human-readable identifiers surfaced alongside opaque IDs
- [ ] Error messages point at the next action

**Implementation**

- [ ] Every tool declares `name` and `annotations` in the decorator
- [ ] All four annotations set explicitly
- [ ] Every input is a Pydantic `BaseModel` with `extra="forbid"` and `Field()` constraints
- [ ] Every field has an explicit type and a description
- [ ] Docstrings document args, the full return schema, examples, and error strings
- [ ] No manual validation duplicating what Pydantic already enforces

**Python quality**

- [ ] Type hints throughout
- [ ] All network operations `async`, with `httpx` used through async context managers
- [ ] Module-level constants in `UPPER_CASE`
- [ ] Server name follows `{service}_mcp`
- [ ] Logging goes to stderr; no `print()` anywhere on the stdio path

**Configuration**

- [ ] Dependencies declared in `pyproject.toml`
- [ ] Secrets read from environment, validated at startup

**Code quality**

- [ ] Pagination implemented on every list tool, default limit 20–50
- [ ] Large responses truncate against a `CHARACTER_LIMIT` constant with an explicit message
- [ ] Filtering offered for potentially large result sets
- [ ] Timeouts and connection errors handled on every network call
- [ ] Shared logic extracted; return types consistent across similar operations

**Build**

- [ ] Server starts and serves over the configured transport
- [ ] All imports resolve
- [ ] Inspector lists every tool with the correct annotations
- [ ] Error scenarios return a readable message rather than a traceback
