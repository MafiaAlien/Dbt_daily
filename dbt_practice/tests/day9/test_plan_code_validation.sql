/* V9 For every invoice, the int's
`plan_code` equals the plan of the customer's version **with the greatest `dbt_valid_from`
not after `invoiced_at`**. Write it **without reading `dbt_valid_to`**. A test that reuses the
model's join predicate inherits the model's bug, which was Day 7's V10. This one reaches the
same answer by a different route, so the two can disagree.
*/

select 
    i.invoice_id,
    i.plan_code,
    i.invoiced_at,
    s.plan_code as covering_plan_code,
    s.dbt_valid_from as covering_from
from 
    {{ ref('int_d9_invoice_revenue') }} i
    join {{ ref('snap_d9_customers')}} s 
    on i.customer_id = s.customer_id and i.invoiced_at > s.dbt_valid_from
where i.plan_code is distinct from s.plan_code