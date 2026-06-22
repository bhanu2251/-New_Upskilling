-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = ['TRANSACTION_ID', 'LINE_ID', 'ACCOUNTING_BOOK_ID'],
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'core_gl']
    )
}}

{#
    Model   : transactionaccountingline
    Layer   : Silver
    Grain   : 1 row per posted accounting line (TRANSACTION + TRANSACTIONLINE + ACCOUNTINGBOOK)
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — POSTING=TRUE filter, CAST to NUMBER, FX translation logic,
              DEDUP via QUALIFY ROW_NUMBER() DESC on _FIVETRAN_SYNCED
    Source  : {{ source('raw', 'TRANSACTIONACCOUNTINGLINE') }}
    Notes   : POSTING=TRUE filter applied.
              Voided/non-posting transactions excluded via inner join to silver.transaction.
              Line context joined from silver.transactionline (department, class, location, item).
              Account classification joined from silver.account (accttype, cashflowrate, generalrate).
              FX rates joined from silver.consolidatedexchangerate.
              FX translation: AVERAGERATE for P&L, CURRENTRATE for BS assets/liabilities,
              HISTORICALRATE for equity. Defaults to 1 if rate is missing (USD→USD rows).
              All camelCase and reserved Bronze column names double-quoted.
              TRANSACTION, TRANSACTIONLINE, ACCOUNTINGBOOK, ACCOUNT,
              NETAMOUNT, DEFERREVREC double-quoted.
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'TRANSACTIONACCOUNTINGLINE') }}
    WHERE POSTING = TRUE
    {% if is_incremental() %}
      AND "_FIVETRAN_SYNCED" > (SELECT MAX(SILVER_UPDATED_ON_TS_UTC) FROM {{ this }})
    {% endif %}

),

-- inner join enforces void=false, posting=true from transaction header
CLEAN_TRANSACTIONS AS (

    SELECT
        TRANSACTION_ID,
        TRANSACTION_REF,
        TRANSACTION_TYPE,
        TRANSACTION_DATE,
        POSTING_PERIOD_ID,
        SUBSIDIARY_ID,
        ENTITY_ID,
        CURRENCY_ID
    FROM {{ ref('transaction') }}

),

-- line-level context (department, class, location, item)
CLEAN_LINES AS (

    SELECT
        TRANSACTION_ID,
        LINE_ID,
        DEPARTMENT_ID,
        CLASS_ID,
        LOCATION_ID,
        ITEM_ID,
        IS_COGS,
        ELIMINATE
    FROM {{ ref('transactionline') }}

),

-- account classification (accttype, cashflowrate, generalrate, financial_statement)
CLEAN_ACCOUNTS AS (

    SELECT
        ACCOUNT_ID,
        ACCOUNT_NUMBER,
        ACCOUNT_TYPE,
        ACCOUNT_FULL_NAME                                               AS ACCOUNT_NAME,
        FINANCIAL_STATEMENT,
        PL_CATEGORY,
        BS_CATEGORY,
        CASH_FLOW_RATE,
        GENERAL_RATE
    FROM {{ ref('account') }}

),

-- FX rates: period + from_subsidiary → USD (exclude elimination subsidiaries)
FX_RATES AS (

    SELECT
        PERIOD_ID,
        FROM_SUBSIDIARY_ID,
        AVERAGE_RATE,
        CURRENT_RATE,
        HISTORICAL_RATE
    FROM {{ ref('consolidatedexchangerate') }}
    WHERE IS_ELIMINATION_SUBSIDIARY = FALSE

),

JOINED AS (

    SELECT
        TAL."TRANSACTION"                                               AS TRANSACTION_ID,
        TAL."TRANSACTIONLINE"                                           AS LINE_ID,
        TAL."ACCOUNTINGBOOK"                                            AS ACCOUNTING_BOOK_ID,
        TAL."ACCOUNT"                                                   AS ACCOUNT_ID,

        -- transaction header context
        T.TRANSACTION_REF,
        T.TRANSACTION_TYPE,
        T.TRANSACTION_DATE,
        T.POSTING_PERIOD_ID                                             AS PERIOD_ID,
        T.SUBSIDIARY_ID,
        T.ENTITY_ID,
        T.CURRENCY_ID                                                   AS TRANSACTION_CURRENCY_ID,

        -- line context
        TL.DEPARTMENT_ID,
        TL.CLASS_ID,
        TL.LOCATION_ID,
        TL.ITEM_ID,
        TL.IS_COGS,
        TL.ELIMINATE,

        -- account classification context
        A.ACCOUNT_NUMBER,
        A.ACCOUNT_TYPE,
        A.ACCOUNT_NAME,
        A.FINANCIAL_STATEMENT,
        A.PL_CATEGORY,
        A.BS_CATEGORY,
        A.CASH_FLOW_RATE,
        A.GENERAL_RATE,

        -- debit / credit / net amounts (functional currency)
        CAST(COALESCE(TAL.DEBIT,       0) AS NUMBER(38,2))              AS DEBIT_AMOUNT,
        CAST(COALESCE(TAL.CREDIT,      0) AS NUMBER(38,2))              AS CREDIT_AMOUNT,
        CAST(COALESCE(TAL.AMOUNT,      0) AS NUMBER(38,2))              AS AMOUNT,
        CAST(COALESCE(TAL."NETAMOUNT", 0) AS NUMBER(38,2))              AS NET_AMOUNT,
        CAST(COALESCE(TAL.AMOUNT,      0) AS NUMBER(38,2))              AS FUNCTIONAL_AMOUNT,

        -- FX translation to USD using correct rate type per account classification
        CASE
            WHEN A.FINANCIAL_STATEMENT = 'P&L'
                THEN CAST(COALESCE(TAL.AMOUNT, 0) AS NUMBER(38,2))
                     * COALESCE(FX.AVERAGE_RATE,   1)
            WHEN A.BS_CATEGORY IN ('Current Asset', 'Non-Current Asset',
                                   'Current Liability', 'Non-Current Liability')
                THEN CAST(COALESCE(TAL.AMOUNT, 0) AS NUMBER(38,2))
                     * COALESCE(FX.CURRENT_RATE,   1)
            WHEN A.BS_CATEGORY = 'Equity'
                THEN CAST(COALESCE(TAL.AMOUNT, 0) AS NUMBER(38,2))
                     * COALESCE(FX.HISTORICAL_RATE, 1)
            ELSE CAST(COALESCE(TAL.AMOUNT,   0) AS NUMBER(38,2))
                 * COALESCE(FX.AVERAGE_RATE,   1)
        END                                                             AS REPORTING_AMOUNT_USD,

        -- FX rates applied (for auditability)
        COALESCE(FX.AVERAGE_RATE,    1)                                 AS FX_AVERAGE_RATE,
        COALESCE(FX.CURRENT_RATE,    1)                                 AS FX_CURRENT_RATE,
        COALESCE(FX.HISTORICAL_RATE, 1)                                 AS FX_HISTORICAL_RATE,

        -- flags
        TAL.POSTING                                                     AS IS_POSTING,
        TAL."DEFERREVREC"                                               AS IS_DEFERRED_REV_REC,

        TAL."_FIVETRAN_SYNCED"                                          AS FIVETRAN_SYNCED_AT

    FROM SOURCE TAL

    -- only lines from posted, non-voided transactions
    INNER JOIN CLEAN_TRANSACTIONS T
        ON TAL."TRANSACTION" = T.TRANSACTION_ID

    -- department, class, location, item context
    LEFT JOIN CLEAN_LINES TL
        ON TAL."TRANSACTION"     = TL.TRANSACTION_ID
       AND TAL."TRANSACTIONLINE" = TL.LINE_ID

    -- account classification and FX rate type
    LEFT JOIN CLEAN_ACCOUNTS A
        ON TAL."ACCOUNT" = A.ACCOUNT_ID

    -- FX rates: match period + subsidiary → USD
    LEFT JOIN FX_RATES FX
        ON T.POSTING_PERIOD_ID = FX.PERIOD_ID
       AND T.SUBSIDIARY_ID     = FX.FROM_SUBSIDIARY_ID

    WHERE TAL."ACCOUNT" IS NOT NULL

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY TAL."TRANSACTION", TAL."TRANSACTIONLINE", TAL."ACCOUNTINGBOOK"
        ORDER BY TAL."_FIVETRAN_SYNCED" DESC
    ) = 1

),

FINAL AS (

    SELECT
        -- surrogate key (composite)
        MD5(
            CAST(TRANSACTION_ID      AS VARCHAR) || '|' ||
            CAST(LINE_ID             AS VARCHAR) || '|' ||
            CAST(ACCOUNTING_BOOK_ID  AS VARCHAR)
        )                                                               AS SURROGATE_KEY,

        JOINED.*,

        {% if is_incremental() %}
        COALESCE(
            (SELECT MIN(EXISTING.SILVER_CREATED_ON_TS_UTC)
             FROM {{ this }} EXISTING
             WHERE EXISTING.TRANSACTION_ID     = JOINED.TRANSACTION_ID
               AND EXISTING.LINE_ID            = JOINED.LINE_ID
               AND EXISTING.ACCOUNTING_BOOK_ID = JOINED.ACCOUNTING_BOOK_ID),
            CURRENT_TIMESTAMP()
        )                                                               AS SILVER_CREATED_ON_TS_UTC,
        {% else %}
        CURRENT_TIMESTAMP()                                             AS SILVER_CREATED_ON_TS_UTC,
        {% endif %}
        CURRENT_TIMESTAMP()                                             AS SILVER_UPDATED_ON_TS_UTC,
        CAST(NULL AS TIMESTAMP_NTZ)                                     AS SILVER_DELETED_ON_TS_UTC

    FROM JOINED

)

SELECT * FROM FINAL
