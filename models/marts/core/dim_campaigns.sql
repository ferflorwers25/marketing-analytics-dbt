-- One row per campaign: latest name seen in the performance data, plus current status and
-- budget from the SCD2 snapshot of campaign settings.
with latest_name as (
    select client_id, platform, campaign_id, campaign_name
    from {{ ref('int_ad_performance__unioned') }}
    qualify row_number() over (
        partition by client_id, platform, campaign_id
        order by date_day desc, extracted_at desc
    ) = 1
),

current_settings as (
    select platform, cast(campaign_id as varchar) as campaign_id, status, daily_budget, dbt_valid_from as settings_valid_from
    from {{ ref('snap_campaign_settings') }}
    where dbt_valid_to is null
)

select
    {{ dbt_utils.generate_surrogate_key(['latest_name.client_id', 'latest_name.platform', 'latest_name.campaign_id']) }} as campaign_key,
    latest_name.client_id,
    latest_name.platform,
    latest_name.campaign_id,
    latest_name.campaign_name,
    current_settings.status,
    current_settings.daily_budget,
    current_settings.settings_valid_from
from latest_name
left join current_settings
    on latest_name.platform = current_settings.platform
    and latest_name.campaign_id = current_settings.campaign_id
