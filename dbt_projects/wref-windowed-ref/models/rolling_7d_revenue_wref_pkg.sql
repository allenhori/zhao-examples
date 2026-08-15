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

-- Same 7-day rolling revenue as rolling_7d_revenue_wref, but wref() comes
-- from the zhao_dbt_utils package (packages.yml + dbt deps), not the
-- standalone macro file -- so the call is namespaced, zhao_utils.wref(...),
-- instead of the bare wref() the standalone install gives you.
select
    order_date,
    sum(amount) as revenue_7d
from {{ zhao_utils.wref('mb_orders_daily') }} mb_orders_daily
group by 1
