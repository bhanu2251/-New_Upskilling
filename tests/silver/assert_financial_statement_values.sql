-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
-- Test    : FINANCIAL_STATEMENT must only be 'P&L', 'Balance Sheet', or 'Unclassified'.
-- Asserts : No unexpected or NULL values in FINANCIAL_STATEMENT.
-- Returns : Rows with unexpected values — test passes when 0 rows returned.

SELECT
    ACCOUNT_ID,
    FINANCIAL_STATEMENT
FROM {{ ref('account') }}
WHERE FINANCIAL_STATEMENT NOT IN ('P&L', 'Balance Sheet', 'Unclassified')
   OR FINANCIAL_STATEMENT IS NULL
