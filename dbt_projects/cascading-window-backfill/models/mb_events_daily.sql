{{
  config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='event_at',
    batch_size='day',
    begin='2026-01-01'
  )
}}

-- Entry Node: one row per raw event, batched daily. No meta.zhao here -- this
-- model reads directly from the raw seed, not from another microbatch model,
-- so there's nothing for zhao-dbt-plan to widen a read of.
select
    event_id,
    event_at,
    device_id,
    event_type
from {{ ref('raw_events') }}
