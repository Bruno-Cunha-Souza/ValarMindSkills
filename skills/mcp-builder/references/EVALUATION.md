# EVALUATION — mcp-builder

> Reference companion for the [mcp-builder](../SKILL.md) skill. Phase 4 of the lifecycle: proving an LLM can actually use the server you just built.

## Why this phase exists

A server that compiles, lists its tools, and returns valid JSON can still be unusable — descriptions too vague to pick the right tool, results too bloated to reason over, errors that dead-end. The evaluation is the only step that measures the thing the server is for.

Ten realistic questions. If an agent with nothing but this server can answer them, the server works. If it cannot, the failures point at exactly which tool description, response format, or pagination behaviour is at fault.

## Question requirements

**Core**

- Exactly 10 questions.
- **Read-only.** Answering must never require a write or destructive operation.
- **Independent.** No question depends on another's answer.
- **Complex.** Each requires multiple tool calls — potentially dozens — and multi-hop reasoning across sub-questions.
- **Realistic.** Something a human would actually want to know.

**Depth**

- Multi-hop: the answer comes from combining findings, not from one lookup.
- May require paging through several pages of results.
- **Do not reuse keywords from the target content.** Use synonyms and descriptions. A question containing the exact title of the record it is about is a keyword-search exercise, not an evaluation.

**Stability**

- The answer must not change over time. Look at closed conversations, launched projects, archived repositories, completed quarters.
- Never count live state — reactions on a post, replies in a thread, current members of a group, open issues right now.

## Answer requirements

- A **single verifiable value**, checked by direct string comparison.
- Not a list, object, or array — those can come back in any order and cannot be compared.
- Not free-form natural language, unless the exact string is what is being asked for.
- Clear and unambiguous. One correct rendering, not three defensible ones.
- Prefer human-readable forms.

**Vary the answer type across the ten.** User concepts (ID, name, email), channel concepts (ID, name, topic), message concepts (ID, timestamp, month/day/year), plus booleans and counts of stable historical sets.

## Process

### Step 1 — Documentation inspection

Read the target API's documentation: available endpoints and functionality. Where it is ambiguous, fetch more from the web. Parallelize this as much as possible.

### Step 2 — Tool inspection

List the tools the server exposes. Inspect the server directly — input and output schemas, descriptions, docstrings — **without calling any tool yet**.

### Step 3 — Build understanding

Repeat steps 1 and 2 until the picture is solid. Iterate. Start forming the kinds of tasks worth creating. **At no stage read the server's source code** — the evaluation measures what an agent can do from the tool surface alone, and reading the implementation contaminates that.

### Step 4 — Read-only content inspection

Now call the tools, restricted to **read-only, non-destructive operations**. The goal is to find specific content concrete enough to build realistic questions around. Call nothing that modifies state.

### Step 5 — Generate the questions

Write the 10 questions against every rule above.

### Step 6 — Verify and write the file

Solve each question yourself using the server, in parallel, to establish the ground truth. Then:

- Replace any answer that turned out wrong with the verified one.
- Remove any `<qa_pair>` that turned out to need a write or destructive operation.
- Accumulate all answers first, write the file once at the end — solving ten multi-hop questions serially will exhaust context before the file is written.

## Output format

```xml
<evaluation>
  <qa_pair>
    <question>Find discussions about AI model launches with animal codenames. One model needed a specific safety designation that uses the format ASL-X. What number X was being determined for the model named after a spotted wild cat?</question>
    <answer>3</answer>
  </qa_pair>
  <qa_pair>
    <question>...</question>
    <answer>...</answer>
  </qa_pair>
</evaluation>
```

## Running the evaluation

No harness, no API key, no separate runner: the agent holding this skill is the LLM the evaluation is for.

1. Set the graded `evaluation.xml` aside — **do not read the answers** during the run.
2. Answer all 10 questions using only the server's tools, in parallel where possible.
3. Compare the produced answers against the file by direct string comparison.
4. Report the score and, for each miss, the specific cause: which tool was not found, which description misled, which response was truncated or too large, which error message dead-ended.

Step 4 is the deliverable. A score with no diagnosis is a number; a score with causes is a list of fixes.

**Acceptance:** 8 of 10. Below that, the fault is in the server, not the questions — go back to Phase 2 and fix the tool surface the misses point at.

## Examples

### Good

**Multi-hop exploration**

> Find the repository that was archived in Q3 2023 and had previously been the most forked project in the organization. What was the primary programming language used in that repository?
> → `Python`

Several searches, filters archived repositories, then inspects details. Historical, so stable.

**Context without keyword matching**

> Locate the initiative focused on improving customer onboarding that was completed in late 2023. The project lead created a retrospective document after completion. What was the lead's role title at that time?
> → `Product Manager`

Never names the project. Forces the agent to find completed projects in a window, then identify a person, then a point-in-time attribute.

**Complex aggregation**

> Among all bugs reported in January 2024 that were marked as critical priority, which assignee resolved the highest percentage of their assigned bugs within 48 hours? Provide the assignee's username.
> → `alex_eng`

Filtering, grouping, rate calculation, timestamp arithmetic — and enough volume to exercise pagination.

**Synthesis across data types**

> Find the account that upgraded from the Starter to Enterprise plan in Q4 2023 and had the highest annual contract value. What industry does this account operate in?
> → `Healthcare`

Crosses subscription events, a time window, and a value comparison before reaching the answer.

### Poor

**Answer changes over time**

> How many open issues are currently assigned to the engineering team?
> → `47`

Wrong tomorrow. Evaluations must be re-runnable.

**Solvable by keyword search**

> Find the pull request with title 'Add authentication feature' and tell me who created it.
> → `developer123`

One exact-match search. Tests nothing about exploration or tool composition.

**Ambiguous answer format**

> List all the repositories that have Python as their primary language.
> → `repo1, repo2, repo3, data-pipeline, ml-tools`

A list has no canonical order, so direct string comparison cannot verify it.

## Tips

1. **Think and plan before generating.** The ten questions are the product; drafting them carelessly wastes the whole phase.
2. **Parallelize.** Both the exploration and the verification. It saves wall-clock and, more importantly, context.
3. **Stay realistic.** Questions humans would actually ask.
4. **Push the limits.** Easy questions pass on a broken server and teach nothing.
5. **Prefer historical data and closed concepts** — that is what makes answers stable.
6. **Verify by solving.** An unverified answer key is a guess.
7. **Iterate.** What you learn while verifying usually improves two or three of the questions.
