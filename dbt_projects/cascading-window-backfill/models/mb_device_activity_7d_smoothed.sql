{{
  config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='activity_date',
    batch_size='day',
    begin='2026-01-01',
    meta={'zhao': {'lookback': 6, 'lookahead': 1}}
  )
}}

-- Tier 3: a 7-day trailing average of Tier 2's daily event_count, smoothed
-- with a 1-day-ahead correction pass for late-arriving Tier 2 rows.
-- meta.zhao.lookback: 6 / lookahead: 1 tells zhao-dbt-plan that a correct
-- read of mb_device_activity_3d needs 6 extra days behind AND 1 extra day
-- ahead of this model's own batch window -- this is the tier where the
-- cascading math actually compounds with Tier 2's own lookback.
select
    device_id,
    activity_date,
    avg(event_count) over (
        partition by device_id
        order by activity_date
        rows between 6 preceding and current row
    ) as event_count_7d_avg
from {{ ref('mb_device_activity_3d') }}
