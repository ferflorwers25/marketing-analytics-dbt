-- Client x platform x day: what we spent, what the platform claims, and what the store attributes.
-- The gap between platform-reported and store-attributed conversions is the number clients ask about most.
with spend as (
    select
        client_id,
        platform,
        date_day,
        sum(spend_usd)                     as spend_usd,
        sum(impressions)                   as impressions,
        sum(clicks)                        as clicks,
        sum(platform_conversions)          as platform_conversions,
        sum(platform_conversion_value_usd) as platform_conversion_value_usd
    from {{ ref('fct_ad_performance_daily') }}
    group by 1, 2, 3
),

attributed as (
    select
        client_id,
        platform,
        order_date                         as date_day,
        count(*)                           as attributed_orders,
        sum(order_total)                   as attributed_revenue_usd
    from {{ ref('fct_orders') }}
    where is_paid and platform != 'unattributed'
    group by 1, 2, 3
),

joined as (
    select
        coalesce(spend.client_id, attributed.client_id) as client_id,
        coalesce(spend.platform, attributed.platform)   as platform,
        coalesce(spend.date_day, attributed.date_day)   as date_day,
        coalesce(spend.spend_usd, 0)                    as spend_usd,
        coalesce(spend.impressions, 0)                  as impressions,
        coalesce(spend.clicks, 0)                       as clicks,
        coalesce(spend.platform_conversions, 0)         as platform_conversions,
        coalesce(spend.platform_conversion_value_usd, 0) as platform_conversion_value_usd,
        coalesce(attributed.attributed_orders, 0)       as attributed_orders,
        coalesce(attributed.attributed_revenue_usd, 0)  as attributed_revenue_usd
    from spend
    full outer join attributed
        on spend.client_id = attributed.client_id
        and spend.platform = attributed.platform
        and spend.date_day = attributed.date_day
)

select
    {{ dbt_utils.generate_surrogate_key(['client_id', 'platform', 'date_day']) }} as channel_day_key,
    *,
    {{ dbt_utils.safe_divide('attributed_revenue_usd', 'spend_usd') }}            as roas_attributed,
    {{ dbt_utils.safe_divide('platform_conversion_value_usd', 'spend_usd') }}     as roas_platform_reported,
    {{ dbt_utils.safe_divide('platform_conversions - attributed_orders', 'attributed_orders') }} as conversion_overreport_rate
from joined
