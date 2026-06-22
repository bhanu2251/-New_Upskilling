-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
-- Test    : silver.transactionaccountingline must contain only posting GL lines.
-- Asserts : IS_POSTING = TRUE for every row.
-- Returns : Rows where IS_POSTING = FALSE — test passes when 0 rows returned.

SELECT
    TRANSACTION_ID,
    LINE_ID,
    ACCOUNTING_BOOK_ID,
    IS_POSTING
FROM {{ ref('transactionaccountingline') }}
WHERE IS_POSTING = FALSE
