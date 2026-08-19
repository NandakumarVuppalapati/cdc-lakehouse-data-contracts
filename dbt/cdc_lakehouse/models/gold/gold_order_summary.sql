{#
  Business-level mart: one row per order, joined and aggregated from Silver.
  This model has an enforced Model Contract (see schema.yml) — dbt checks
  the actual query output's column names/types against the declared contract
  before it will build the table. A breaking upstream change (a renamed or
  retyped column anywhere in the Silver models this depends on) fails the
  `dbt run` here with a contract violation, not a silently wrong dashboard
  three steps downstream. This is contract layer 2 (see docs/architecture.md).
#}
{{ config(materialized='table') }}

select
    o.order_id,
    o.customer_id,
    c.full_name as customer_name,
    c.email as customer_email,
    o.status,
    o.placed_at,
    count(oi.order_item_id) as item_count,
    coalesce(sum(oi.quantity * oi.unit_price_cents), 0) as total_amount_cents
from {{ ref('silver_orders') }} o
left join {{ ref('silver_customers') }} c on o.customer_id = c.customer_id
left join {{ ref('silver_order_items') }} oi on o.order_id = oi.order_id
group by o.order_id, o.customer_id, c.full_name, c.email, o.status, o.placed_at
