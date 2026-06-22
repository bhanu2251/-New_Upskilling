-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
-- Test    : silver.transaction must contain no voided records.
-- Asserts : IS_VOID = FALSE for every row.
-- Returns : Rows where IS_VOID = TRUE — test passes when 0 rows returned.

SELECT
    TRANSACTION_ID,
    IS_VOID
FROM {{ ref('transaction') }}
WHERE IS_VOID = TRUE
