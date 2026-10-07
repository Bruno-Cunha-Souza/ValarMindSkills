# Third-Party Notices

## mcp-builder (Anthropic)

The `skills/mcp-builder/` skill is derived from [anthropics/skills/skills/mcp-builder](https://github.com/anthropics/skills/tree/main/skills/mcp-builder), which is licensed under the Apache License, Version 2.0. This is the only Apache-licensed upstream in this repository; the full license text is not reproduced here, but the notice below is retained as required by §4 of that license.

```
Copyright 2026 Anthropic, PBC.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

Upstream license text: <https://github.com/anthropics/skills/blob/main/skills/mcp-builder/LICENSE.txt>

### Modifications from upstream

- Rewritten into the ValarMindSkills Lifecycle archetype: three-field frontmatter (upstream's `license:` field stripped per repository convention), `SKILL.md` reduced to a phase router with the deep content pushed into `references/`.
- **Rust added and made the default language.** Upstream covers only Python and TypeScript and recommends TypeScript; `references/RUST.md` (`rmcp`, tool router macros, `ToolAnnotations`, `StreamableHttpServerConfig`) has no upstream equivalent and was written for this port.
- **Transport guidance rewritten for protocol revision `2026-07-28`**, which removed protocol-level sessions and resumable SSE streams. Upstream's guides still describe stateful sessions and the deprecated HTTP+SSE transport.
- **The Python evaluation harness was not ported.** Upstream's `scripts/` (`evaluation.py`, `connections.py`, `example_evaluation.xml`, `requirements.txt`) would require a Python dependency and an `ANTHROPIC_API_KEY` to run a loop the invoking agent already performs, and `scripts/` inside a skill is an anti-pattern in this repository. Phase 4 runs through the agent instead, keeping the question rules, the XML format, and the good/poor question catalog intact.
- Reference companions renamed to the repository's `UPPERCASE.md` convention and given the standard breadcrumb header.

| Reference | Upstream file |
| :--- | :--- |
| `BEST_PRACTICES.md` | `reference/mcp_best_practices.md` |
| `TYPESCRIPT.md` | `reference/node_mcp_server.md` |
| `PYTHON.md` | `reference/python_mcp_server.md` |
| `EVALUATION.md` | `reference/evaluation.md` (harness sections removed) |
| `RUST.md` | — (no upstream equivalent) |
