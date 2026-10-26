-- One row per Google Ads campaign-day (latest extraction). Cost arrives in micros.
with source as (
    select * from {{ source('raw', 'google_ads_campaign_stats') }}
),

latest as (
    select *
    from source
    qualify row_number() over (
        partition by customer_id, campaign_id, segments_date
        order by _extracted_at desc
    ) = 1
)

select
    cast(customer_id as varchar)                         as account_id,
    cast(campaign_id as varchar)                         as campaign_id,
    campaign_name,
    cast(segments_date as date)                          as date_day,
    'USD'                                                as currency,
    cast(cost_micros / 1000000.0 as decimal(18, 2))      as spend,
    cast(impressions as bigint)                          as impressions,
    cast(clicks as bigint)                               as clicks,
    cast(round(conversions, 0) as bigint)                as platform_conversions,
    cast(conversions_value as decimal(18, 2))            as platform_conversion_value,
    cast(_extracted_at as timestamp)                     as extracted_at
from latest
