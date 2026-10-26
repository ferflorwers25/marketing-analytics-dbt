-- One row per Shopify order, with the UTM parameters parsed out of the landing URL.
with source as (
    select * from {{ source('raw', 'shopify_orders') }}
)

select
    cast(order_id as varchar)                                           as order_id,
    shop_domain,
    cast(created_at as timestamp)                                       as created_at,
    cast(cast(created_at as timestamp) as date)                         as order_date,
    cast(total_price as decimal(18, 2))                                 as order_total,
    upper(currency)                                                     as currency,
    lower(financial_status)                                             as financial_status,
    lower(financial_status) = 'paid'                                    as is_paid,
    lower({{ extract_url_param('landing_site', 'utm_source') }})        as utm_source,
    lower({{ extract_url_param('landing_site', 'utm_medium') }})        as utm_medium,
    {{ extract_url_param('landing_site', 'utm_campaign') }}             as utm_campaign
from source
