-- Total spend per client and platform in the fact table must match the deduplicated staging
-- models (converted to USD) to the cent. Catches double-counted restatements and lost rows.
with fact as (
    select client_id, platform, sum(spend_usd) as spend_usd
    from {{ ref('fct_ad_performance_daily') }}
    group by 1, 2
),

staged as (
    select client_id, platform, sum(spend_usd) as spend_usd
    from {{ ref('int_ad_performance__unioned') }}
    group by 1, 2
)

select staged.client_id, staged.platform, staged.spend_usd as staged_spend, fact.spend_usd as fact_spend
from staged
full outer join fact
    on staged.client_id = fact.client_id
    and staged.platform = fact.platform
where abs(coalesce(staged.spend_usd, 0) - coalesce(fact.spend_usd, 0)) > 0.01
