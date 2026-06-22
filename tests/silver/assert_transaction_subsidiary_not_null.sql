-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
-- Test    : silver.transaction SUBSIDIARY_ID must not be NULL for posting transactions.
-- Asserts : Every posted transaction is attributed to a known owning subsidiary.
-- Returns : Rows where SUBSIDIARY_ID is NULL — test passes when 0 rows returned.
-- Note    : This test validates the FIX where SUBSIDIARY_ID was incorrectly sourced
--           from TOSUBSIDIARY (intercompany destination) instead of SUBSIDIARY
--           (transaction's own owning entity). TOSUBSIDIARY is NULL for all
--           non-intercompany transactions, which caused blank subsidiary joins in Gold.

SELECT
    TRANSACTION_ID,
    TRANSACTION_REF,
    TRANSACTION_TYPE,
    TRANSACTION_DATE,
    SUBSIDIARY_ID,
    INTERCO_TO_SUBSIDIARY_ID
FROM {{ ref('transaction') }}
WHERE SUBSIDIARY_ID IS NULL
