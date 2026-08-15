select
    customer_id,
    first_name,
    email,
    first_name as full_name
from {{ ref('stg_customers') }}
