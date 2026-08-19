{{ config(materialized='table') }}

with ranked as (

    select
        coalesce(after.order_item_id, before.order_item_id) as order_item_id,
        after.order_id as order_id,
        after.product_id as product_id,
        after.quantity as quantity,
        after.unit_price_cents as unit_price_cents,
        op,
        ts_ms,
        row_number() over (
            partition by coalesce(after.order_item_id, before.order_item_id)
            order by ts_ms desc
        ) as rn
    from {{ source('bronze', 'order_items') }}

)

select
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price_cents
from ranked
where rn = 1
  and op != 'd'
