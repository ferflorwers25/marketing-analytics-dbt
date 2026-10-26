select
    client_id,
    client_name,
    shop_domain,
    attribution_window_days,
    cast(onboarded_on as date) as onboarded_on
from {{ ref('clients') }}
