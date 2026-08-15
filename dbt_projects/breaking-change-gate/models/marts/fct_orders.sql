select
    o.order_id,
    o.customer_id,
    c.full_name as customer_name,
    o.order_date,
    o.status,
    o.amount
from {{ ref('stg_orders') }} o
left join {{ ref('dim_customers') }} c
    on o.customer_id = c.customer_id
