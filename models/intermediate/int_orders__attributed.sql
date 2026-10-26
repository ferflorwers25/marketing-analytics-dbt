-- Paid orders attributed last-click to a platform and campaign through their UTM parameters.
-- Orders without a known utm_source stay unattributed (platform = 'unattributed').
with orders as (
    select * from {{ ref('stg_shopify__orders') }}
),

clients as (
    select client_id, shop_domain from {{ ref('clients') }}
),

utm_map as (
    select * from {{ ref('utm_source_mapping') }}
)

select
    orders.order_id,
    clients.client_id,
    orders.order_date,
    orders.order_total,
    orders.is_paid,
    orders.utm_source,
    coalesce(utm_map.platform, 'unattributed')                as platform,
    case when utm_map.platform is not null then orders.utm_campaign end as campaign_id
from orders
inner join clients
    on orders.shop_domain = clients.shop_domain
left join utm_map
    on orders.utm_source = utm_map.utm_source_normalized
