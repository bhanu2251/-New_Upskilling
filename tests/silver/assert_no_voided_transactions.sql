-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-18T09:52:56Z UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
-- Test: silver.transaction must contain no voided records.
-- Returns rows if IS_VOID = TRUE exists — test passes when 0 rows returned.

SELECT TRANSACTION_ID, IS_VOID
FROM {{ ref('transaction') }}
WHERE IS_VOID = TRUE
