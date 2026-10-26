-- All platforms at one grain (client, platform, campaign, day) and in one currency (USD).
-- New platforms are added to the list below; everything downstream works unchanged.
{% set platforms = [
    ('meta',       'stg_meta__campaign_daily',       'meta_account_id'),
    ('google_ads', 'stg_google_ads__campaign_daily', 'google_customer_id'),
    ('tiktok',     'stg_tiktok__campaign_daily',     'tiktok_advertiser_id'),
] %}

with clients as (
    select * from {{ ref('clients') }}
),

fx as (
    select * from {{ ref('fx_rates') }}
),

unioned as (
    {% for platform, model, account_column in platforms %}
    select
        clients.client_id,
        '{{ platform }}' as platform,
        perf.*
    from {{ ref(model) }} as perf
    inner join clients
        on perf.account_id = cast(clients.{{ account_column }} as varchar)
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
)

select
    {{ dbt_utils.generate_surrogate_key(['unioned.client_id', 'unioned.platform', 'unioned.campaign_id', 'unioned.date_day']) }} as ad_performance_key,
    unioned.client_id,
    unioned.platform,
    unioned.account_id,
    unioned.campaign_id,
    unioned.campaign_name,
    unioned.date_day,
    unioned.currency                                                         as source_currency,
    cast(unioned.spend * fx.usd_per_unit as decimal(18, 2))                  as spend_usd,
    unioned.impressions,
    unioned.clicks,
    unioned.platform_conversions,
    cast(unioned.platform_conversion_value * fx.usd_per_unit as decimal(18, 2)) as platform_conversion_value_usd,
    unioned.extracted_at
from unioned
inner join fx
    on unioned.currency = fx.currency
