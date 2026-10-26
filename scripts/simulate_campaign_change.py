"""Simulate an account manager editing a campaign (new budget and a pause), to show the SCD2 snapshot.

Usage: python scripts/simulate_campaign_change.py   (then run: dbt snapshot)
"""
import datetime as dt
from pathlib import Path

import duckdb

DB = Path(__file__).resolve().parents[1] / "data" / "warehouse.duckdb"

con = duckdb.connect(str(DB))
now = dt.datetime.now().replace(microsecond=0)
con.execute(
    """
    update raw.campaign_settings
    set daily_budget = daily_budget * 1.5,
        status = case when campaign_name = 'Lookalike 1%' then 'PAUSED' else status end,
        updated_at = ?
    where client_key = 'northwind_apparel' and platform = 'meta'
    """,
    [now],
)
print(con.execute("select platform, campaign_name, status, daily_budget, updated_at from raw.campaign_settings "
                  "where client_key = 'northwind_apparel' and platform = 'meta'").fetchdf().to_string(index=False))
con.close()
