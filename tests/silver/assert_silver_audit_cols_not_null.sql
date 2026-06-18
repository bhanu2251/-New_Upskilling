-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-18T09:52:56Z UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
-- Test: SILVER_CREATED_ON_TS_UTC and SILVER_UPDATED_ON_TS_UTC must never be NULL.
-- Returns rows if NULL audit timestamps exist — test passes when 0 rows returned.

{% set silver_models = [
    'account', 'accountingperiod', 'classification',
    'consolidatedexchangerate', 'currency', 'department',
    'employee', 'entity', 'item', 'location', 'subsidiary',
    'transaction', 'transactionaccountingline', 'transactionline',
    'transactionstatus'
] %}

{% for model in silver_models %}
SELECT
    '{{ model }}'                 AS silver_table,
    SURROGATE_KEY,
    SILVER_CREATED_ON_TS_UTC,
    SILVER_UPDATED_ON_TS_UTC
FROM {{ ref(model) }}
WHERE SILVER_CREATED_ON_TS_UTC IS NULL
   OR SILVER_UPDATED_ON_TS_UTC  IS NULL
{% if not loop.last %} UNION ALL {% endif %}
{% endfor %}
