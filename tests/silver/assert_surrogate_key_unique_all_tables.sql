-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-18T09:52:56Z UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
-- Test: SURROGATE_KEY is unique on every Silver table.
-- Returns rows where duplicates exist — test passes when 0 rows returned.

{% set silver_models = [
    'account', 'accountingperiod', 'classification',
    'consolidatedexchangerate', 'currency', 'department',
    'employee', 'entity', 'item', 'location', 'subsidiary',
    'transaction', 'transactionaccountingline', 'transactionline',
    'transactionstatus'
] %}

{% for model in silver_models %}
SELECT
    '{{ model }}'  AS silver_table,
    SURROGATE_KEY,
    COUNT(*)       AS duplicate_count
FROM {{ ref(model) }}
GROUP BY SURROGATE_KEY
HAVING COUNT(*) > 1
{% if not loop.last %} UNION ALL {% endif %}
{% endfor %}
