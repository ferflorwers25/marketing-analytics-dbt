-- Orders attributed to a platform must point to a campaign we know. A miss usually means a
-- client changed its UTM template; it is reported as a warning, not a failure.
{{ config(severity='warn') }}
select orders.order_id, orders.platform, orders.campaign_id
from {{ ref('fct_orders') }} as orders
left join {{ ref('dim_campaigns') }} as campaigns
    on orders.platform = campaigns.platform
    and orders.campaign_id = campaigns.campaign_id
where orders.platform != 'unattributed'
  and campaigns.campaign_id is null
