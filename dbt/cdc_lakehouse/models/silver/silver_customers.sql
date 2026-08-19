{#
  Bronze -> Silver: collapse the raw Debezium CDC stream into "current state
  per primary key." Standard CDC dedup pattern — rank every event for a key
  by ts_ms descending, keep rank 1, drop it if the latest event was a delete
  (soft-delete: the row simply stops appearing in Silver, matching what a
  real OLTP `DELETE` should mean downstream).

  COALESCE(after.customer_id, before.customer_id) because a delete event has
  after = NULL — the row identity only survives in `before` for that event.
#}
{{ config(materialized='table') }}

with ranked as (

    select
        coalesce(after.customer_id, before.customer_id) as customer_id,
        after.email as email,
        after.full_name as full_name,
        after.country as country,
        try(from_iso8601_timestamp(after.signup_at)) as signup_at,
        op,
        ts_ms,
        row_number() over (
            partition by coalesce(after.customer_id, before.customer_id)
            order by ts_ms desc
        ) as rn
    from {{ source('bronze', 'customers') }}

)

select
    customer_id,
    email,
    full_name,
    country,
    signup_at
from ranked
where rn = 1
  and op != 'd'
