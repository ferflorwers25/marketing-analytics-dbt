"""Generate a SIMULATED multi-client marketing dataset and load it into the raw schema.

The data is fake (fixed random seed) but it reproduces the problems a marketing data team
deals with every day:

- Three ad platforms with different column names and units (Meta spend in currency units,
  Google Ads cost in micros, TikTok dates as timestamps and one account billed in MXN).
- Retroactive restatements: platforms re-send the last 7 days with more conversions, so the
  same campaign-day arrives more than once with a newer _extracted_at.
- A deprecated field: Meta renamed action_values_purchase to purchase_value; newer extracts
  only fill the new column.
- Shopify orders with UTM parameters in the landing URL (some missing, some with messy
  utm_source values like "fb" or "IG"), and refunded orders.
- Platform-reported conversions that are higher than what the store actually attributes.

Usage:
    python scripts/generate_data.py                  # loads into DuckDB (data/warehouse.duckdb)
    python scripts/generate_data.py --csv-only       # only writes data/raw/*.csv (for Snowflake)
"""
from __future__ import annotations

import argparse
import datetime as dt
import random
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
DB = ROOT / "data" / "warehouse.duckdb"

SEED = 42
DAYS = 120
RESTATEMENT_DAYS = 7

CLIENTS = {
    "northwind_apparel": dict(meta="act_1001", google="111-222-3001", tiktok="7001", shop="northwind-apparel.myshopify.com",
                              tiktok_currency="USD", aov=68.0),
    "lumen_skincare": dict(meta="act_2002", google="111-222-4002", tiktok="7002", shop="lumen-skincare.myshopify.com",
                           tiktok_currency="MXN", aov=42.0),
}

CAMPAIGNS = {
    "meta": ["Prospecting - Broad", "Retargeting - 7d", "Advantage+ Shopping", "Lookalike 1%"],
    "google_ads": ["Brand Search", "Non-Brand Search", "Performance Max", "Shopping - Bestsellers"],
    "tiktok": ["Spark Ads - UGC", "Prospecting - Interests", "Retargeting - Video Viewers"],
}
# How much each platform over-reports conversions compared with what the store attributes.
OVER_REPORT = {"meta": 1.35, "google_ads": 1.15, "tiktok": 1.55}
UTM_SOURCES = {"meta": ["facebook", "fb", "instagram", "IG"], "google_ads": ["google", "Google", "adwords"],
               "tiktok": ["tiktok", "TikTok"]}
MXN_PER_USD = 18.0


def main(csv_only: bool) -> None:
    rng = random.Random(SEED)
    # Stable, deterministic campaign ids per client/platform.
    ids: dict[tuple[str, str, int], str] = {}
    counter = 0
    for c in CLIENTS:
        for p, names in CAMPAIGNS.items():
            for i, _ in enumerate(names):
                counter += 1
                prefix = {"meta": "238", "google_ads": "19", "tiktok": "17"}[p]
                ids[(c, p, i)] = f"{prefix}{counter:06d}"

    today = dt.date.today()
    start = today - dt.timedelta(days=DAYS)
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    deprecation_day = today - dt.timedelta(days=30)

    meta_rows, google_rows, tiktok_rows, order_rows, settings_rows = [], [], [], [], []
    order_n = 100000

    for client, cfg in CLIENTS.items():
        for platform, names in CAMPAIGNS.items():
            for i, name in enumerate(names):
                cid = ids[(client, platform, i)]
                budget = rng.choice([80, 120, 150, 200, 250])
                settings_rows.append(dict(client_key=client, platform=platform, campaign_id=cid, campaign_name=name,
                                          status="ACTIVE", daily_budget=budget,
                                          updated_at=(now - dt.timedelta(days=DAYS)).replace(tzinfo=None).isoformat()))
                for d in range(DAYS):
                    day = start + dt.timedelta(days=d)
                    weekend = 1.15 if day.weekday() >= 5 else 1.0
                    spend = round(budget * rng.uniform(0.7, 1.05) * weekend, 2)
                    cpm = rng.uniform(6, 14)
                    impressions = int(spend / cpm * 1000)
                    clicks = int(impressions * rng.uniform(0.008, 0.025))
                    true_orders = max(0, int(clicks * rng.uniform(0.015, 0.04)))
                    reported = int(round(true_orders * OVER_REPORT[platform] * rng.uniform(0.9, 1.1)))
                    reported_value = round(reported * cfg["aov"] * rng.uniform(0.9, 1.1), 2)

                    # Store orders attributed by UTM (the "truth" the warehouse sees).
                    for _ in range(true_orders):
                        order_n += 1
                        created = dt.datetime.combine(day, dt.time(rng.randint(0, 23), rng.randint(0, 59)))
                        src = rng.choice(UTM_SOURCES[platform])
                        status = rng.choices(["paid", "refunded", "pending"], [0.92, 0.05, 0.03])[0]
                        url = f"https://{cfg['shop']}/products/item-{rng.randint(1, 40)}?utm_source={src}&utm_medium=paid&utm_campaign={cid}"
                        order_rows.append(dict(order_id=order_n, shop_domain=cfg["shop"], created_at=created.isoformat(),
                                               total_price=round(cfg["aov"] * rng.uniform(0.6, 1.6), 2), currency="USD",
                                               financial_status=status, landing_site=url))

                    # Extractions: every day is extracted once; the last RESTATEMENT_DAYS are re-sent
                    # with a later _extracted_at and late conversions added (retroactive restatement).
                    extracts = [(now - dt.timedelta(days=(today - day).days - 1, hours=2), 0.85 if (today - day).days <= RESTATEMENT_DAYS else 1.0)]
                    if (today - day).days <= RESTATEMENT_DAYS:
                        extracts.append((now - dt.timedelta(hours=1), 1.0))
                    for extracted_at, share in extracts:
                        conv = int(round(reported * share))
                        value = round(reported_value * share, 2)
                        if platform == "meta":
                            new_field = day >= deprecation_day
                            meta_rows.append(dict(date_start=day.isoformat(), account_id=cfg["meta"], campaign_id=cid,
                                                  campaign_name=name, spend=f"{spend:.2f}", impressions=impressions,
                                                  clicks=clicks, actions_purchase=conv,
                                                  action_values_purchase=None if new_field else value,
                                                  purchase_value=value if new_field else None,
                                                  _extracted_at=extracted_at.isoformat()))
                        elif platform == "google_ads":
                            google_rows.append(dict(segments_date=day.isoformat(), customer_id=cfg["google"], campaign_id=cid,
                                                    campaign_name=name, cost_micros=int(spend * 1_000_000),
                                                    impressions=impressions, clicks=clicks, conversions=float(conv),
                                                    conversions_value=value, _extracted_at=extracted_at.isoformat()))
                        else:
                            fx = MXN_PER_USD if cfg["tiktok_currency"] == "MXN" else 1.0
                            tiktok_rows.append(dict(stat_time_day=f"{day.isoformat()} 00:00:00", advertiser_id=cfg["tiktok"],
                                                    campaign_id=cid, campaign_name=name, currency=cfg["tiktok_currency"],
                                                    spend=round(spend * fx, 2), impressions=impressions, clicks=clicks,
                                                    complete_payment=conv, total_complete_payment_value=round(value * fx, 2),
                                                    _extracted_at=extracted_at.isoformat()))

    # Organic / direct orders with no UTM, so attribution coverage is below 100%.
    for client, cfg in CLIENTS.items():
        for _ in range(int(len(order_rows) * 0.08)):
            order_n += 1
            day = start + dt.timedelta(days=rng.randrange(DAYS))
            order_rows.append(dict(order_id=order_n, shop_domain=cfg["shop"],
                                   created_at=dt.datetime.combine(day, dt.time(rng.randint(0, 23), 0)).isoformat(),
                                   total_price=round(cfg["aov"] * rng.uniform(0.6, 1.6), 2), currency="USD",
                                   financial_status="paid", landing_site=f"https://{cfg['shop']}/"))

    tables = {
        "meta_ads_insights": pd.DataFrame(meta_rows),
        "google_ads_campaign_stats": pd.DataFrame(google_rows),
        "tiktok_ads_report": pd.DataFrame(tiktok_rows),
        "shopify_orders": pd.DataFrame(order_rows),
        "campaign_settings": pd.DataFrame(settings_rows),
    }
    RAW.mkdir(parents=True, exist_ok=True)
    for name, df in tables.items():
        df.to_csv(RAW / f"{name}.csv", index=False)
        print(f"{name:28s} {len(df):>7,} rows")
    if csv_only:
        return

    import duckdb

    con = duckdb.connect(str(DB))
    con.execute("create schema if not exists raw")
    for name in tables:
        con.execute(f"create or replace table raw.{name} as select * from read_csv_auto('{RAW / (name + '.csv')}', header=true)")
    con.close()
    print(f"Loaded into {DB.relative_to(ROOT)} (schema raw)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv-only", action="store_true")
    main(ap.parse_args().csv_only)
