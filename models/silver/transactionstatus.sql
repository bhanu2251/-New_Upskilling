-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'TRANSACTION_STATUS_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'lookup']
    )
}}

{#
    Model   : transactionstatus
    Layer   : Silver
    Grain   : 1 row per transaction status code (unique TRANSACTION_STATUS_ID)
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — NULLIF(TRIM()) on VARCHAR,
              DEDUP via QUALIFY ROW_NUMBER() on natural key (no _FIVETRAN_SYNCED watermark)
    Source  : {{ source('raw', 'TRANSACTIONSTATUS') }}
    Notes   : FIX — QUALIFY dedup added (was missing; no watermark so full refresh always).
              No ISINACTIVE or watermark column — full refresh only.
              All source columns double-quoted (underscore names conflict with reserved words).
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'TRANSACTIONSTATUS') }}

),

RENAMED AS (

    SELECT
        MD5(CAST("TRANSACTION_STATUS_ID" AS VARCHAR))                   AS SURROGATE_KEY,
        "TRANSACTION_STATUS_ID"                                         AS TRANSACTION_STATUS_ID,
        NULLIF(TRIM("TRANSACTION_STATUS_FULL_NAME"), '')                AS STATUS_FULL_NAME,
        NULLIF(TRIM("TRANSACTION_STATUS_NAME"), '')                     AS STATUS_NAME,
        NULLIF(TRIM("TRANSACTION_TYPE"), '')                            AS TRANSACTION_TYPE,
        NULLIF(TRIM("TRAN_CUSTOM_TYPE_ID"), '')                         AS CUSTOM_TYPE_ID

    FROM SOURCE

    -- dedup on natural key (no _FIVETRAN_SYNCED available on this lookup table)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY "TRANSACTION_STATUS_ID"
        ORDER BY "TRANSACTION_STATUS_ID"
    ) = 1

),

FINAL AS (

    SELECT
        RENAMED.*,
        CURRENT_TIMESTAMP()                                             AS SILVER_CREATED_ON_TS_UTC,
        CURRENT_TIMESTAMP()                                             AS SILVER_UPDATED_ON_TS_UTC,
        CAST(NULL AS TIMESTAMP_NTZ)                                     AS SILVER_DELETED_ON_TS_UTC

    FROM RENAMED

)

SELECT * FROM FINAL
