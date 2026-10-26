# Marketing Analytics dbt Project

A dbt project that models paid-media data the way an agency needs it: several clients, three ad
platforms (Meta, Google Ads, TikTok) and Shopify orders, reconciled into one set of trusted
metrics for dashboards and AI agents.

> **The data is simulated.** `scripts/generate_data.py` creates it with a fixed seed. It is fake
> on purpose, but it reproduces the problems real connectors bring: restated conversions,
> deprecated fields, different units and currencies, messy UTM values and platforms that
> over-report conversions.

Runs locally on **DuckDB** with zero setup and on **Snowflake** with the same code
(`profiles.yml` has both targets; warehouse-specific SQL goes through dispatched macros).
Verified end to end on a Snowflake account (key-pair auth, XSMALL warehouse): raw load,
`dbt build`, incremental re-run and reconciliation test all pass.

## What it shows

| Problem | How the project handles it |
|---|---|
| Platforms re-send the last 7 days with late conversions | Staging keeps the latest extraction per campaign-day (`qualify row_number()`), and `fct_ad_performance_daily` is **incremental** (`delete+insert`) with a configurable restatement lookback (`var('restatement_lookback_days')`). A singular test reconciles total spend to the cent after every run. |
| Meta renamed `action_values_purchase` to `purchase_value` | Staging reads both (`coalesce`), so history and new extracts land in one column. |
| Different units and currencies | Google cost micros converted to currency units; TikTok MXN accounts converted to USD through an FX seed. |
| Messy UTMs (`fb`, `IG`, `adwords`) | URL parameters parsed with an adapter-dispatched macro (`regexp_extract` on DuckDB, `regexp_substr` on Snowflake) and mapped to platforms through a seed. Covered by a **dbt unit test**. |
| Platform-reported vs store-attributed conversions | `mart_channel_performance_daily` puts spend, platform-reported value and Shopify-attributed revenue side by side, with both ROAS figures and the over-report rate. |
| Multi-client warehouse | Shared **core** marts for every client, and a **client layer** (`models/clients/`) for client-specific rules, e.g. Lumen Skincare measures ROAS without Brand Search. The core is extended, never forked. |
| Campaign edits (budget, pauses) | **SCD2 snapshot** of campaign settings; `dim_campaigns` reads the current version. |
| One definition of each metric | **Semantic layer** (MetricFlow semantic model + metrics: spend, attributed revenue, ROAS, platform ROAS) on top of a time spine, so dashboards, analysts and an AI agent get the same numbers. |
| Knowing who uses what | **Exposures** for the client dashboard and the AI analyst agent. |
| Stale data | **Source freshness** on `_extracted_at` (warn after 1 day, error after 3). |

## Lineage

```
raw (5 sources) ──► staging (4 views) ──► intermediate (2 ephemeral) ──► core marts ──► semantic layer
     │                                                         │                 └──► client layer (Lumen)
seeds (clients, utm mapping, fx) ─────────────────────────────┘
snapshot (campaign settings, SCD2) ──► dim_campaigns
```

13 models · 3 seeds · 1 snapshot · 40 data tests (generic, custom generic `not_negative`,
`dbt_utils` and singular reconciliation tests) · 1 unit test · 5 metrics · 2 exposures.

## What the simulated data surfaces

| Platform | Spend (USD) | ROAS, store-attributed | ROAS, platform-reported | Conversions over-reported |
|---|---|---|---|---|
| Google Ads | 136,750 | 2.43 | 2.74 | 24% |
| Meta | 129,990 | 2.48 | 3.29 | 47% |
| TikTok | 84,696 | 2.31 | 3.52 | 68% |

(The gaps are built into the generator; the point is that the mart makes them visible per
client, platform and day.)

## Run it

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DBT_PROFILES_DIR=.

python scripts/generate_data.py     # simulated raw data into data/warehouse.duckdb
dbt deps
dbt source freshness
dbt build                           # seeds, snapshot, models, unit and data tests

# incremental run with the restatement window, then reconcile
dbt run -s fct_ad_performance_daily && dbt test -s assert_spend_reconciles_to_platforms

# SCD2: edit a campaign and snapshot again
python scripts/simulate_campaign_change.py && dbt snapshot

dbt docs generate && dbt docs serve
```

### On Snowflake

Authentication uses a key pair, so no password is stored in files or environment variables.

1. In a Snowsight worksheet, run [`scripts/snowflake_setup.sql`](scripts/snowflake_setup.sql)
   (XSMALL auto-suspending warehouse, `MARKETING` database, least-privilege `TRANSFORMER` role).
2. Create a key pair and register the public key on your user:
   ```bash
   mkdir -p ~/.snowflake && cd ~/.snowflake
   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
   openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
   # in Snowsight: alter user <user> set rsa_public_key = '<rsa_key.pub without BEGIN/END lines>';
   ```
3. Run everything (creates a Python 3.12 env, loads the raw data, runs `dbt build`):
   ```bash
   export SNOWFLAKE_ACCOUNT=<orgname-accountname> SNOWFLAKE_USER=<user> SNOWFLAKE_PRIVATE_KEY_PATH=~/.snowflake/rsa_key.p8
   ./scripts/run_on_snowflake.sh
   ```

## CI

GitHub Actions runs the whole flow on every push: generate data, `dbt deps`, source freshness,
`dbt build`, an incremental re-run plus reconciliation, the SCD2 snapshot check and docs.

## How it was built

Built with Claude Code as a pair programmer, with `dbt build` as the gate for every change.
See [docs/ai-workflow.md](docs/ai-workflow.md) for the workflow and its guardrails.

## Project layout

```
models/
  staging/        one folder per source, light cleaning, one row per natural key
  intermediate/   platforms unioned at one grain and currency; orders attributed by UTM
  marts/core/     shared dims, facts and the channel performance mart
  clients/        client-specific logic on top of the core
  semantic/       time spine + semantic models and metrics
macros/           dispatched URL parsing, custom generic test
snapshots/        SCD2 campaign settings
tests/            singular reconciliation tests
scripts/          data generator, Snowflake loader, campaign-edit simulation
```

## License

MIT
