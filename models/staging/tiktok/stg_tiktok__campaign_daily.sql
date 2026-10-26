-- One row per TikTok campaign-day (latest extraction). Dates arrive as timestamps and amounts
-- stay in the advertiser's billing currency here; conversion to USD happens downstream.
with source as (
    select * from {{ source('raw', 'tiktok_ads_report') }}
),

latest as (
    select *
    from source
    qualify row_number() over (
        partition by advertiser_id, campaign_id, stat_time_day
        order by _extracted_at desc
    ) = 1
)

select
    cast(advertiser_id as varchar)                       as account_id,
    cast(campaign_id as varchar)                         as campaign_id,
    campaign_name,
    cast(cast(stat_time_day as timestamp) as date)       as date_day,
    upper(currency)                                      as currency,
    cast(spend as decimal(18, 2))                        as spend,
    cast(impressions as bigint)                          as impressions,
    cast(clicks as bigint)                               as clicks,
    cast(complete_payment as bigint)                     as platform_conversions,
    cast(total_complete_payment_value as decimal(18, 2)) as platform_conversion_value,
    cast(_extracted_at as timestamp)                     as extracted_at
from latest
