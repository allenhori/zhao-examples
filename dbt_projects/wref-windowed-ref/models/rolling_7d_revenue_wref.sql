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

-- wref(): reads meta.zhao.lookback/lookahead on this same model and widens
-- the read of mb_orders_daily to the full 7-day window, instead of dbt's
-- own narrow single-batch default.
select
    order_date,
    sum(amount) as revenue_7d
from {{ wref('mb_orders_daily') }} mb_orders_daily
group by 1
