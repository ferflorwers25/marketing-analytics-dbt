# AI-assisted workflow

This project was built with Claude Code as a pair programmer. The rule: the AI can propose and
write anything, but nothing is kept unless `dbt build` passes.

## The loop

1. **Spec first.** Describe the grain, keys and business rule in plain language before any SQL
   (for example: "one row per client, platform, campaign and day; platforms restate the last
   7 days").
2. **Generate a slice.** One layer at a time: sources, staging, intermediate, marts. Never the
   whole DAG in one prompt.
3. **Gate.** `dbt parse` then `dbt build`. Failures go back into the conversation as-is.
4. **Test the claim, not the code.** Every rule gets a test: uniqueness at the stated grain,
   a reconciliation test for money, a unit test for parsing logic.
5. **Review the diff.** Read the generated SQL before committing; ask "why" for anything that
   is not obvious and write the answer as a comment.

## Guardrails that mattered

- **Reconcile money to the cent.** `assert_spend_reconciles_to_platforms` compares the fact
  table with the deduplicated staging totals. It is the test that catches double-counted
  restatements in incremental models.
- **Portable SQL.** Warehouse-specific functions go through `adapter.dispatch` macros, so the
  same project runs on DuckDB (local, CI) and Snowflake.
- **Semantic layer for AI consumers.** An AI agent should query metrics (ROAS, spend), not raw
  tables, so its answers match the dashboard.
- **Simulated data with real problems.** The generator encodes restatements, a deprecated
  field, currencies and messy UTMs, so the models are tested against the failures that happen
  in production, not against clean data.

## Reusable pattern

"Spec → slice → gate → test → review" is the pattern I would document as a team standard: it
keeps the speed of AI-generated code while every merged change is covered by a test that
checks the business rule.
