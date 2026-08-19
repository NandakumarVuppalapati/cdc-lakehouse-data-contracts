{{ config(materialized='table') }}

with ranked as (

    select
        coalesce(after.order_id, before.order_id) as order_id,
        after.customer_id as customer_id,
        after.status as status,
        try(from_iso8601_timestamp(after.placed_at)) as placed_at,
        try(from_iso8601_timestamp(after.updated_at)) as updated_at,
        op,
        ts_ms,
        row_number() over (
            partition by coalesce(after.order_id, before.order_id)
            order by ts_ms desc
        ) as rn
    from {{ source('bronze', 'orders') }}

)

select
    order_id,
    customer_id,
    status,
    placed_at,
    updated_at
from ranked
where rn = 1
  and op != 'd'
