# TYPESCRIPT — mcp-builder

> Reference companion for the [mcp-builder](../SKILL.md) skill. Language-agnostic rules live in [BEST_PRACTICES.md](BEST_PRACTICES.md).

Official SDK: [`@modelcontextprotocol/sdk`](https://github.com/modelcontextprotocol/typescript-sdk). Live docs via Context7 `/modelcontextprotocol/typescript-sdk`.

**Pick TypeScript when** the server ships as an MCPB bundle or is distributed with `npx`, or when the client ecosystem you target expects a Node package. Otherwise the default is [Rust](RUST.md).

## Setup

```sh
npm init -y
npm i @modelcontextprotocol/sdk zod
npm i -D typescript @types/node
```

Package name is `{service}-mcp-server`. `tsconfig.json` runs in strict mode; the build emits `dist/index.js` as the entry point.

## Project structure

```text
{service}-mcp-server/
├── package.json
├── tsconfig.json
├── README.md
├── src/
│   ├── index.ts          # McpServer initialization and transport bootstrap
│   ├── types.ts          # TypeScript interfaces
│   ├── tools/            # one file per domain
│   ├── services/         # API clients and shared utilities
│   ├── schemas/          # Zod schemas
│   └── constants.ts      # API_URL, CHARACTER_LIMIT, defaults
└── dist/                 # build output, entry point dist/index.js
```

## Input schemas

Zod, with `.strict()` so an agent's misspelled parameter fails loudly instead of being dropped. Constraints and `.describe()` text are what the agent reads.

```ts
export const UserSearchInputSchema = z.object({
  query: z.string().min(1).describe("Search string matched against names and emails, e.g. 'team:marketing'"),
  limit: z.number().int().min(1).max(100).default(20).describe("Maximum results to return"),
  offset: z.number().int().min(0).default(0).describe("Number of results to skip, for pagination"),
  response_format: z.enum(["markdown", "json"]).default("markdown"),
}).strict();

export type UserSearchInput = z.infer<typeof UserSearchInputSchema>;
```

## Registering tools

`server.registerTool` with the full configuration: `title`, `description`, `inputSchema`, `annotations`, and an `outputSchema` wherever the tool returns structured data.

```ts
server.registerTool(
  "acme_search_users",
  {
    title: "Search Acme Users",
    description: `Search for users in Acme by name, email, or team.

Searches existing user profiles, supporting partial matches and filters. Does NOT
create or modify users.

Args:
  - query (string): Search string matched against names/emails
  - limit (number): Maximum results, 1-100 (default: 20)
  - offset (number): Results to skip for pagination (default: 0)
  - response_format ('markdown' | 'json'): Output format (default: 'markdown')

Returns:
  {
    "total": number, "count": number, "offset": number,
    "users": [{ "id": string, "name": string, "email": string,
                "team": string, "active": boolean }],
    "has_more": boolean, "next_offset": number
  }

Examples:
  - "Find all marketing team members" -> query="team:marketing"
  - "Search for John's account" -> query="john"
  - Don't use when: you need to create a user (use acme_create_user)

Errors:
  - "Error: rate limit exceeded" on 429
  - "No users found matching '<query>'" when the search is empty`,
    inputSchema: UserSearchInputSchema,
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: true,
    },
  },
  async (params: UserSearchInput) => {
    try {
      const data = await makeApiRequest<UsersPage>("users/search", "GET", undefined, {
        q: params.query,
        limit: params.limit,
        offset: params.offset,
      });

      const users = data.users ?? [];
      const total = data.total ?? 0;

      if (!users.length) {
        return { content: [{ type: "text", text: `No users found matching '${params.query}'` }] };
      }

      const hasMore = total > params.offset + users.length;
      const output = {
        total,
        count: users.length,
        offset: params.offset,
        users,
        has_more: hasMore,
        ...(hasMore ? { next_offset: params.offset + users.length } : {}),
      };

      const text =
        params.response_format === "markdown"
          ? renderUsersMarkdown(params.query, total, users)
          : JSON.stringify(output, null, 2);

      // Text for the agent to read, structure for the client to process.
      return { content: [{ type: "text", text }], structuredContent: output };
    } catch (error) {
      return { isError: true, content: [{ type: "text", text: handleApiError(error) }] };
    }
  }
);
```

## Errors

Tool failures come back inside the result with `isError: true`, never as a thrown protocol error. Every message names a next step; none of them leak internal detail.

```ts
export function handleApiError(error: unknown): string {
  if (axios.isAxiosError(error)) {
    switch (error.response?.status) {
      case 404: return "Error: resource not found. Check the ID.";
      case 403: return "Error: permission denied for this resource.";
      case 429: return "Error: rate limit exceeded. Retry after 30s, or narrow the query with filter='active_only'.";
    }
    if (error.code === "ECONNABORTED") return "Error: request timed out. Retry with a smaller limit.";
  }
  console.error("unhandled api error", error);   // stderr — never stdout under stdio
  return "Error: upstream request failed.";
}
```

## Transports

### stdio

```ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const server = new McpServer({ name: "acme-mcp-server", version: "1.0.0" });

async function runStdio() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("MCP server running via stdio");
}

runStdio().catch((error) => {
  console.error("Server error:", error);
  process.exit(1);
});
```

`console.log` writes to stdout, which under stdio *is* the protocol channel. Use `console.error` for everything. A single stray log desynchronizes the JSON-RPC stream.

### Streamable HTTP

Match the `2026-07-28` shape: stateless, JSON responses, no session IDs minted or echoed, `405` on `GET`/`DELETE` at the MCP endpoint. Validate the `Origin` header and bind to `127.0.0.1` when serving locally. See [BEST_PRACTICES.md](BEST_PRACTICES.md#transports).

## Build and test

```sh
npm run build
node dist/index.js --help
npx @modelcontextprotocol/inspector node dist/index.js
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

- [ ] Every tool registered via `registerTool` with the full configuration object
- [ ] Every tool has `title`, `description`, `inputSchema`, and `annotations`
- [ ] All four annotations set explicitly
- [ ] Zod schemas use `.strict()` and carry constraints plus `.describe()` on every field
- [ ] Descriptions document args, return schema, use/don't-use examples, and error strings
- [ ] `outputSchema` and `structuredContent` used where the tool returns structured data

**TypeScript quality**

- [ ] `strict` enabled in `tsconfig.json`
- [ ] Interfaces defined for all data structures
- [ ] No `any` — use `unknown` and narrow
- [ ] Async functions have explicit `Promise<T>` return types
- [ ] Error handling narrows with type guards (`axios.isAxiosError`, `z.ZodError`)

**Configuration**

- [ ] `package.json` declares every dependency
- [ ] Build produces working JavaScript in `dist/`, entry point `dist/index.js`
- [ ] Package named `{service}-mcp-server`
- [ ] Secrets read from environment, validated at startup

**Code quality**

- [ ] Pagination implemented on every list tool, default limit 20–50
- [ ] Large responses truncate against `CHARACTER_LIMIT` with an explicit message
- [ ] Filtering offered for potentially large result sets
- [ ] Timeouts and connection errors handled on every network call
- [ ] Shared logic extracted; return types consistent across similar operations

**Build**

- [ ] `npm run build` completes with no errors
- [ ] `dist/index.js` created and executable
- [ ] Server starts: `node dist/index.js --help`
- [ ] All imports resolve
- [ ] Inspector lists every tool with the correct annotations
- [ ] stdio path writes nothing to stdout except protocol frames
