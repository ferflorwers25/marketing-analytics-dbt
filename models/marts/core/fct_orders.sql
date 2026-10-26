-- One row per order with its last-click attribution.
select * from {{ ref('int_orders__attributed') }}
