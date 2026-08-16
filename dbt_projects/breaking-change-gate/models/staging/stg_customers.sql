select
    id as customer_id,
    first_name,
    last_name,
    email,
    email as email_lower
from {{ ref('raw_customers') }}
