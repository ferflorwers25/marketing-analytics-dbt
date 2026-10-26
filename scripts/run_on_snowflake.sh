#!/usr/bin/env bash
# Runs the whole project on Snowflake: load the simulated raw data, then dbt build.
# Needs: SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PRIVATE_KEY_PATH (see README).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SNOWFLAKE_ACCOUNT:?export SNOWFLAKE_ACCOUNT first}"
: "${SNOWFLAKE_USER:?export SNOWFLAKE_USER first}"
: "${SNOWFLAKE_PRIVATE_KEY_PATH:?export SNOWFLAKE_PRIVATE_KEY_PATH first}"

# Python 3.12 environment. uv (https://docs.astral.sh/uv/) downloads Python if needed.
if command -v uv >/dev/null 2>&1; then
  [ -d .venv ] || uv venv --python 3.12 .venv
  source .venv/bin/activate
  uv pip install -q -r requirements.txt dbt-snowflake "snowflake-connector-python[pandas]"
else
  [ -d .venv ] || python3 -m venv .venv
  source .venv/bin/activate
  pip install -q --upgrade pip
  pip install -q -r requirements.txt dbt-snowflake "snowflake-connector-python[pandas]"
fi

export DBT_PROFILES_DIR=. DBT_TARGET=snowflake
python scripts/generate_data.py --csv-only
python scripts/load_to_snowflake.py
dbt deps
dbt debug
dbt source freshness
dbt build
dbt run -s fct_ad_performance_daily
dbt test -s fct_ad_performance_daily assert_spend_reconciles_to_platforms
echo "Done: the project ran on Snowflake."
