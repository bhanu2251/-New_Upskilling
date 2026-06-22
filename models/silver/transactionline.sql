-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = ['TRANSACTION_ID', 'LINE_ID'],
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'transactional']
    )
}}

{#
    Model   : transactionline
    Layer   : Silver
    Grain   : 1 row per transaction line (TRANSACTION + ID composite key)
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — MAINLINE=FALSE, TAXLINE=FALSE filters, CAST to NUMBER(38,2),
              DEDUP via QUALIFY ROW_NUMBER() DESC on _FIVETRAN_SYNCED
    Source  : {{ source('raw', 'TRANSACTIONLINE') }}
    Notes   : MAINLINE=FALSE (no header summary lines) and TAXLINE=FALSE filters applied.
              Only lines from posted non-voided transactions flow through via
              inner join to silver.transaction.
              TRANSACTION, CLASS, DEPARTMENT, LOCATION, ENTITY, SUBSIDIARY,
              FOREIGNAMOUNT, CREDITFOREIGNAMOUNT, DEBITFOREIGNAMOUNT,
              NETAMOUNT, MAINLINE, ISCOGS, EXPENSEACCOUNT, TAXLINE, ITEM,
              ITEMTYPE double-quoted.
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'TRANSACTIONLINE') }}
    WHERE "MAINLINE" = FALSE
      AND "TAXLINE"  = FALSE
    {% if is_incremental() %}
      AND "_FIVETRAN_SYNCED" > (SELECT MAX(SILVER_UPDATED_ON_TS_UTC) FROM {{ this }})
    {% endif %}

),

-- inner join ensures only lines from posted, non-voided transactions pass through
POSTED_TRANSACTIONS AS (

    SELECT TRANSACTION_ID
    FROM {{ ref('transaction') }}

),

FILTERED AS (

    SELECT S.*
    FROM SOURCE S
    INNER JOIN POSTED_TRANSACTIONS PT
        ON S."TRANSACTION" = PT.TRANSACTION_ID

),

RENAMED AS (

    SELECT
        MD5(
            CAST("TRANSACTION" AS VARCHAR) || '|' || CAST(ID AS VARCHAR)
        )                                                               AS SURROGATE_KEY,

        -- composite primary key
        "TRANSACTION"                                                   AS TRANSACTION_ID,
        ID                                                              AS LINE_ID,

        -- dimension foreign keys
        "DEPARTMENT"                                                    AS DEPARTMENT_ID,
        "CLASS"                                                         AS CLASS_ID,
        "LOCATION"                                                      AS LOCATION_ID,
        "ENTITY"                                                        AS ENTITY_ID,
        "SUBSIDIARY"                                                    AS SUBSIDIARY_ID,

        -- amounts (functional currency)
        CAST(COALESCE("FOREIGNAMOUNT",       0) AS NUMBER(38,2))        AS FOREIGN_AMOUNT,
        CAST(COALESCE("CREDITFOREIGNAMOUNT", 0) AS NUMBER(38,2))        AS CREDIT_FOREIGN_AMOUNT,
        CAST(COALESCE("DEBITFOREIGNAMOUNT",  0) AS NUMBER(38,2))        AS DEBIT_FOREIGN_AMOUNT,
        CAST(COALESCE("NETAMOUNT",           0) AS NUMBER(38,2))        AS NET_AMOUNT,

        -- memo
        NULLIF(TRIM(MEMO), '')                                          AS LINE_MEMO,

        -- flags
        "MAINLINE"                                                      AS IS_MAINLINE,
        "ISCOGS"                                                        AS IS_COGS,
        "EXPENSEACCOUNT"                                                AS EXPENSE_ACCOUNT_ID,
        "TAXLINE"                                                       AS IS_TAX_LINE,
        "ITEM"                                                          AS ITEM_ID,
        NULLIF(TRIM("ITEMTYPE"), '')                                    AS ITEM_TYPE,
        ELIMINATE                                                       AS ELIMINATE,

        "_FIVETRAN_SYNCED"                                              AS FIVETRAN_SYNCED_AT

    FROM FILTERED

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY "TRANSACTION", ID
        ORDER BY "_FIVETRAN_SYNCED" DESC
    ) = 1

),

FINAL AS (

    SELECT
        RENAMED.*,
        {% if is_incremental() %}
        COALESCE(
            (SELECT MIN(EXISTING.SILVER_CREATED_ON_TS_UTC)
             FROM {{ this }} EXISTING
             WHERE EXISTING.TRANSACTION_ID = RENAMED.TRANSACTION_ID
               AND EXISTING.LINE_ID        = RENAMED.LINE_ID),
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
