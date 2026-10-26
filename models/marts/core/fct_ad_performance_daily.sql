{{
    config(
        materialized='incremental',
        unique_key='ad_performance_key',
        incremental_strategy='delete+insert',
        on_schema_change='append_new_columns'
    )
}}
-- Campaign-day performance for every client and platform, in USD.
-- Incremental: each run re-processes the last N days (var restatement_lookback_days) because the
-- platforms restate recent conversions. Older days are left untouched.
select
    ad_performance_key,
    client_id,
    platform,
    campaign_id,
    date_day,
    source_currency,
    spend_usd,
    impressions,
    clicks,
    platform_conversions,
    platform_conversion_value_usd,
    extracted_at
from {{ ref('int_ad_performance__unioned') }}

{% if is_incremental() %}
where date_day >= (
    select {{ dbt.dateadd('day', -1 * var('restatement_lookback_days'), 'max(date_day)') }}
    from {{ this }}
)
{% endif %}
