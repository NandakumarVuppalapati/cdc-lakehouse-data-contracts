{{ config(materialized='table') }}

with ranked as (

    select
        coalesce(after.product_id, before.product_id) as product_id,
        after.sku as sku,
        after.name as name,
        after.price_cents as price_cents,
        after.category as category,
        op,
        ts_ms,
        row_number() over (
            partition by coalesce(after.product_id, before.product_id)
            order by ts_ms desc
        ) as rn
    from {{ source('bronze', 'products') }}

)

select
    product_id,
    sku,
    name,
    price_cents,
    category
from ranked
where rn = 1
  and op != 'd'
