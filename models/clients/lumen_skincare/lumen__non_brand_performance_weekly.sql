-- CLIENT LAYER (Lumen Skincare only). Lumen judges paid media without Brand Search, because
-- people searching the brand name would have bought anyway. That rule is specific to this
-- client, so it lives here on top of the shared core instead of changing the core marts.
with campaigns as (
    select client_id, platform, campaign_id, campaign_name
    from {{ ref('dim_campaigns') }}
    where client_id = 'lumen_skincare'
      and lower(campaign_name) not like '%brand search%'
      and lower(campaign_name) not like 'brand %'
),

spend as (
    select
        cast({{ dbt.date_trunc('week', 'perf.date_day') }} as date) as week_start,
        perf.platform,
        sum(perf.spend_usd)                          as spend_usd
    from {{ ref('fct_ad_performance_daily') }} as perf
    inner join campaigns
        on perf.client_id = campaigns.client_id
        and perf.platform = campaigns.platform
        and perf.campaign_id = campaigns.campaign_id
    group by 1, 2
),

revenue as (
    select
        cast({{ dbt.date_trunc('week', 'orders.order_date') }} as date) as week_start,
        orders.platform,
        sum(orders.order_total)                          as attributed_revenue_usd
    from {{ ref('fct_orders') }} as orders
    inner join campaigns
        on orders.client_id = campaigns.client_id
        and orders.platform = campaigns.platform
        and orders.campaign_id = campaigns.campaign_id
    where orders.is_paid
    group by 1, 2
)

select
    spend.week_start,
    spend.platform,
    spend.spend_usd,
    coalesce(revenue.attributed_revenue_usd, 0) as attributed_revenue_usd,
    {{ dbt_utils.safe_divide('coalesce(revenue.attributed_revenue_usd, 0)', 'spend.spend_usd') }} as non_brand_roas
from spend
left join revenue
    on spend.week_start = revenue.week_start
    and spend.platform = revenue.platform
