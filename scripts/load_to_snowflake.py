"""Load the simulated raw CSVs into Snowflake (schema RAW) so the same dbt project runs there.

Prerequisites: a Snowflake account (the 30-day trial works), `pip install dbt-snowflake
snowflake-connector-python[pandas]`, a key pair registered on the user (see README) and these
environment variables: SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PRIVATE_KEY_PATH, and
optionally SNOWFLAKE_ROLE, SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DATABASE.

Usage:
    python scripts/generate_data.py --csv-only
    python scripts/load_to_snowflake.py
    DBT_TARGET=snowflake dbt build
"""
import os
from pathlib import Path

import pandas as pd
import snowflake.connector
from snowflake.connector.pandas_tools import write_pandas

RAW = Path(__file__).resolve().parents[1] / "data" / "raw"
TABLES = ["meta_ads_insights", "google_ads_campaign_stats", "tiktok_ads_report", "shopify_orders", "campaign_settings"]
TIMESTAMPS = {"_extracted_at", "updated_at"}

con = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    private_key_file=os.path.expanduser(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]),
    role=os.environ.get("SNOWFLAKE_ROLE", "TRANSFORMER"),
    warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "TRANSFORMING"),
    database=os.environ.get("SNOWFLAKE_DATABASE", "MARKETING"),
)
con.cursor().execute("create schema if not exists RAW")
for name in TABLES:
    df = pd.read_csv(RAW / f"{name}.csv")
    for col in TIMESTAMPS & set(df.columns):
        df[col] = pd.to_datetime(df[col], utc=True).dt.tz_localize(None)
    df.columns = [c.lower() for c in df.columns]
    ok, _, rows, _ = write_pandas(con, df, table_name=name, schema="RAW", auto_create_table=True,
                                  overwrite=True, quote_identifiers=False, use_logical_type=True)
    print(f"{name:28s} {rows:>7,} rows  {'ok' if ok else 'FAILED'}")
con.close()
