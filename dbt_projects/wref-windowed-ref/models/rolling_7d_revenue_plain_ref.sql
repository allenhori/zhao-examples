{{
  config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='order_date',
    batch_size='day',
    begin='2026-01-01',
    meta={'zhao': {'lookback': 6, 'lookahead': 0}}
  )
}}

-- Plain ref(): dbt's own microbatch filtering silently applies only THIS
-- model's own single-day batch window to the read of mb_orders_daily,
-- ignoring meta.zhao.lookback entirely -- a 7-day rolling sum computed
-- from one day of input.
select
    order_date,
    sum(amount) as revenue_7d
from {{ ref('mb_orders_daily') }}
group by 1
