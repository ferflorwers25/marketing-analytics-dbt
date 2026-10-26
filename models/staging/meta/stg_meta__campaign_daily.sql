-- One row per Meta campaign-day. Meta re-sends recent days with late conversions, so keep only
-- the latest extraction. Meta also renamed action_values_purchase to purchase_value: read both.
with source as (
    select * from {{ source('raw', 'meta_ads_insights') }}
),

latest as (
    select *
    from source
    qualify row_number() over (
        partition by account_id, campaign_id, date_start
        order by _extracted_at desc
    ) = 1
)

select
    cast(account_id as varchar)                                   as account_id,
    cast(campaign_id as varchar)                                  as campaign_id,
    campaign_name,
    cast(date_start as date)                                      as date_day,
    'USD'                                                         as currency,
    cast(spend as decimal(18, 2))                                 as spend,
    cast(impressions as bigint)                                   as impressions,
    cast(clicks as bigint)                                        as clicks,
    cast(actions_purchase as bigint)                              as platform_conversions,
    cast(coalesce(purchase_value, action_values_purchase) as decimal(18, 2)) as platform_conversion_value,
    cast(_extracted_at as timestamp)                              as extracted_at
from latest
