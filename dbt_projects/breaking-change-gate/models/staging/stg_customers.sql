select
    id as customer_id,
    first_name,
    email
from {{ ref('raw_customers') }}
