-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
-- Test    : silver.transaction must contain only posting records.
-- Asserts : IS_POSTING = TRUE for every row.
-- Returns : Rows where IS_POSTING = FALSE — test passes when 0 rows returned.

SELECT
    TRANSACTION_ID,
    IS_POSTING
FROM {{ ref('transaction') }}
WHERE IS_POSTING = FALSE
