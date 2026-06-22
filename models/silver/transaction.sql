-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'TRANSACTION_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'transactional']
    )
}}

{#
    Model   : transaction
    Layer   : Silver
    Grain   : 1 row per transaction (unique TRANSACTION.ID)
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — filters VOID=FALSE, POSTING=TRUE, _FIVETRAN_DELETED=FALSE
              STATUS decoded via left join to transactionstatus
              DEDUP via QUALIFY ROW_NUMBER() DESC on _FIVETRAN_SYNCED
    Source  : {{ source('raw', 'TRANSACTION') }}
    Notes   : FIX — SUBSIDIARY (not TOSUBSIDIARY) maps to SUBSIDIARY_ID.
              TOSUBSIDIARY is the intercompany destination subsidiary — kept separately
              as INTERCO_TO_SUBSIDIARY_ID.
              VOID, POSTING, _FIVETRAN_DELETED filters applied at source CTE.
              TYPE, STATUS, ENTITY, CURRENCY, EMPLOYEE, TOSUBSIDIARY, TRANID,
              TRANDATE, RECORDTYPE, POSTINGPERIOD, EXCHANGERATE double-quoted.
              STATUS decoded from silver.transactionstatus via ref().
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'TRANSACTION') }}
    WHERE VOID              = FALSE
      AND POSTING           = TRUE
      AND _FIVETRAN_DELETED = FALSE
    {% if is_incremental() %}
      AND "_FIVETRAN_SYNCED" > (SELECT MAX(SILVER_UPDATED_ON_TS_UTC) FROM {{ this }})
    {% endif %}

),

STATUS_LOOKUP AS (

    SELECT
        STATUS_NAME,
        STATUS_FULL_NAME,
        TRANSACTION_TYPE
    FROM {{ ref('transactionstatus') }}

),

RENAMED AS (

    SELECT
        MD5(CAST(T.ID AS VARCHAR))                                      AS SURROGATE_KEY,

        -- primary key
        T.ID                                                            AS TRANSACTION_ID,

        -- identifiers
        NULLIF(TRIM("TRANID"), '')                                      AS TRANSACTION_REF,
        NULLIF(TRIM("TYPE"), '')                                        AS TRANSACTION_TYPE,
        NULLIF(TRIM("RECORDTYPE"), '')                                  AS RECORD_TYPE,

        -- dates
        CAST("TRANDATE" AS DATE)                                        AS TRANSACTION_DATE,
        "POSTINGPERIOD"                                                 AS POSTING_PERIOD_ID,

        -- foreign keys
        "ENTITY"                                                        AS ENTITY_ID,

        -- FIX: SUBSIDIARY is the transaction's own owning subsidiary
        -- TOSUBSIDIARY is the intercompany destination — kept separately below
        "SUBSIDIARY"                                                    AS SUBSIDIARY_ID,

        -- status (raw code + decoded from lookup)
        NULLIF(TRIM("STATUS"), '')                                      AS STATUS_CODE,
        SL.STATUS_NAME                                                  AS STATUS_NAME,
        SL.STATUS_FULL_NAME                                             AS STATUS_FULL_NAME,

        -- currency and rate
        "CURRENCY"                                                      AS CURRENCY_ID,
        CAST(COALESCE("EXCHANGERATE", 1) AS NUMBER(38,9))               AS EXCHANGE_RATE,

        -- memo
        NULLIF(TRIM(MEMO), '')                                          AS MEMO,

        -- flags (always FALSE/TRUE after WHERE filter — carried for downstream tests)
        VOID                                                            AS IS_VOID,
        POSTING                                                         AS IS_POSTING,

        -- employee
        "EMPLOYEE"                                                      AS EMPLOYEE_ID,

        -- intercompany fields
        "INTERCOTRANSACTION"                                            AS INTERCO_TRANSACTION_ID,
        NULLIF(TRIM("INTERCOSTATUS"), '')                               AS INTERCO_STATUS,
        "INTERCOADJ"                                                    AS IS_INTERCO_ADJ,
        "TOSUBSIDIARY"                                                  AS INTERCO_TO_SUBSIDIARY_ID,

        -- reversal fields
        "ISREVERSAL"                                                    AS IS_REVERSAL,
        REVERSAL                                                        AS REVERSAL_TRANSACTION_ID,
        CAST("REVERSALDATE" AS DATE)                                    AS REVERSAL_DATE,

        T."_FIVETRAN_SYNCED"                                            AS FIVETRAN_SYNCED_AT

    FROM SOURCE T
    LEFT JOIN STATUS_LOOKUP SL
        ON NULLIF(TRIM(T."STATUS"), '')  = SL.STATUS_NAME
       AND NULLIF(TRIM(T."TYPE"), '')    = SL.TRANSACTION_TYPE

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY T.ID
        ORDER BY T."_FIVETRAN_SYNCED" DESC
    ) = 1

),

FINAL AS (

    SELECT
        RENAMED.*,
        {% if is_incremental() %}
        COALESCE(
            (SELECT MIN(EXISTING.SILVER_CREATED_ON_TS_UTC)
             FROM {{ this }} EXISTING
             WHERE EXISTING.TRANSACTION_ID = RENAMED.TRANSACTION_ID),
            CURRENT_TIMESTAMP()
        )                                                               AS SILVER_CREATED_ON_TS_UTC,
        {% else %}
        CURRENT_TIMESTAMP()                                             AS SILVER_CREATED_ON_TS_UTC,
        {% endif %}
        CURRENT_TIMESTAMP()                                             AS SILVER_UPDATED_ON_TS_UTC,
        CAST(NULL AS TIMESTAMP_NTZ)                                     AS SILVER_DELETED_ON_TS_UTC

    FROM RENAMED

)

SELECT * FROM FINAL
