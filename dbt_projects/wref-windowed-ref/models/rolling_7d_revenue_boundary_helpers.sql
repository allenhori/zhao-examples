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

-- A third way to get the same widened window: hand-write the WHERE clause
-- yourself (the documented dbt pattern for rolling-window microbatch models
-- -- ref(...).render() opts out of dbt's automatic single-batch filtering),
-- using zhao_window_start()/zhao_window_end() instead of hardcoding the
-- day-count. Same meta.zhao.lookback: 6 as the two models above, same
-- resulting 7-day window -- these two macros are for exactly this case:
-- you want a custom WHERE clause (e.g. an extra predicate alongside the
-- window), not a full wref() replacement for ref().
select
    order_date,
    sum(amount) as revenue_7d
from {{ ref('mb_orders_daily').render() }}
where order_date >= {{ zhao_utils.zhao_window_start('mb_orders_daily') }}
  and order_date <  {{ zhao_utils.zhao_window_end('mb_orders_daily') }}
group by 1
