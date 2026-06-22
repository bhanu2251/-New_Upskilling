-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
-- Test    : SURROGATE_KEY is unique on every Silver table.
-- Asserts : No duplicate SURROGATE_KEY values across all 15 Silver models.
-- Returns : Rows where duplicates exist — test passes when 0 rows returned.
-- Note    : QUALIFY dedup added to all reference tables in this update;
--           this test validates that fix is working end-to-end.

{% set silver_models = [
    'account', 'accountingperiod', 'classification',
    'consolidatedexchangerate', 'currency', 'department',
    'employee', 'entity', 'item', 'location', 'subsidiary',
    'transaction', 'transactionaccountingline', 'transactionline',
    'transactionstatus'
] %}

{% for model in silver_models %}
SELECT
    '{{ model }}'  AS SILVER_TABLE,
    SURROGATE_KEY,
    COUNT(*)       AS DUPLICATE_COUNT
FROM {{ ref(model) }}
GROUP BY SURROGATE_KEY
HAVING COUNT(*) > 1
{% if not loop.last %} UNION ALL {% endif %}
{% endfor %}
