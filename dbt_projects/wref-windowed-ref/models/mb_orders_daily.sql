{{
  config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='order_date',
    batch_size='day',
    begin='2026-01-01'
  )
}}

select order_id, order_date, customer_id, amount
from {{ ref('raw_orders') }}
