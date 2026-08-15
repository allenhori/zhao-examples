{{
  config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='activity_date',
    batch_size='day',
    begin='2026-01-01',
    meta={'zhao': {'lookback': 2, 'lookahead': 0}}
  )
}}

-- Tier 2: a 3-day trailing count of events per device (today + 2 days back),
-- read from the Tier 1 microbatch model. meta.zhao.lookback: 2 tells
-- zhao-dbt-plan (and, if this model used wref() instead of ref(), the wref()
-- macro itself) that a correct read of mb_events_daily needs 2 extra days
-- behind this model's own batch window.
select
    device_id,
    cast(event_at as date) as activity_date,
    count(*) as event_count
from {{ ref('mb_events_daily') }}
group by 1, 2
