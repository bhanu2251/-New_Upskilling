-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-18T09:52:56Z UTC.
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
    Cleaning: inline — POSTING=TRUE filter, CAST to NUMBER, FX translation logic
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

WITH source AS (

    SELECT *
    FROM {{ source('raw', 'TRANSACTIONACCOUNTINGLINE') }}
    WHERE POSTING = TRUE
    {% if is_incremental() %}
      AND "_FIVETRAN_SYNCED" > (SELECT MAX(SILVER_UPDATED_ON_TS_UTC) FROM {{ this }})
    {% endif %}

),

-- inner join enforces void=false, posting=true from transaction header
clean_transactions AS (

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
clean_lines AS (

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
clean_accounts AS (

    SELECT
        ACCOUNT_ID,
        ACCOUNT_NUMBER,
        ACCOUNT_TYPE,
        ACCOUNT_FULL_NAME   AS ACCOUNT_NAME,
        FINANCIAL_STATEMENT,
        PL_CATEGORY,
        BS_CATEGORY,
        CASH_FLOW_RATE,
        GENERAL_RATE
    FROM {{ ref('account') }}

),

-- FX rates: period + from_subsidiary → USD (exclude elimination subsidiaries)
fx_rates AS (

    SELECT
        PERIOD_ID,
        FROM_SUBSIDIARY_ID,
        AVERAGE_RATE,
        CURRENT_RATE,
        HISTORICAL_RATE
    FROM {{ ref('consolidatedexchangerate') }}
    WHERE IS_ELIMINATION_SUBSIDIARY = FALSE

),

joined AS (

    SELECT
        tal."TRANSACTION"                                               AS TRANSACTION_ID,
        tal."TRANSACTIONLINE"                                           AS LINE_ID,
        tal."ACCOUNTINGBOOK"                                            AS ACCOUNTING_BOOK_ID,
        tal."ACCOUNT"                                                   AS ACCOUNT_ID,

        -- transaction header context
        t.TRANSACTION_REF,
        t.TRANSACTION_TYPE,
        t.TRANSACTION_DATE,
        t.POSTING_PERIOD_ID                                             AS PERIOD_ID,
        t.SUBSIDIARY_ID,
        t.ENTITY_ID,
        t.CURRENCY_ID                                                   AS TRANSACTION_CURRENCY_ID,

        -- line context
        tl.DEPARTMENT_ID,
        tl.CLASS_ID,
        tl.LOCATION_ID,
        tl.ITEM_ID,
        tl.IS_COGS,
        tl.ELIMINATE,

        -- account classification context
        a.ACCOUNT_NUMBER,
        a.ACCOUNT_TYPE,
        a.ACCOUNT_NAME,
        a.FINANCIAL_STATEMENT,
        a.PL_CATEGORY,
        a.BS_CATEGORY,
        a.CASH_FLOW_RATE,
        a.GENERAL_RATE,

        -- debit / credit / net amounts (functional currency)
        CAST(COALESCE(tal.DEBIT,       0) AS NUMBER(38,2))              AS DEBIT_AMOUNT,
        CAST(COALESCE(tal.CREDIT,      0) AS NUMBER(38,2))              AS CREDIT_AMOUNT,
        CAST(COALESCE(tal.AMOUNT,      0) AS NUMBER(38,2))              AS AMOUNT,
        CAST(COALESCE(tal."NETAMOUNT", 0) AS NUMBER(38,2))              AS NET_AMOUNT,
        CAST(COALESCE(tal.AMOUNT,      0) AS NUMBER(38,2))              AS FUNCTIONAL_AMOUNT,

        -- FX translation to USD using correct rate type per account classification
        CASE
            WHEN a.FINANCIAL_STATEMENT = 'P&L'
                THEN CAST(COALESCE(tal.AMOUNT, 0) AS NUMBER(38,2))
                     * COALESCE(fx.AVERAGE_RATE,   1)
            WHEN a.BS_CATEGORY IN ('Current Asset', 'Non-Current Asset',
                                   'Current Liability', 'Non-Current Liability')
                THEN CAST(COALESCE(tal.AMOUNT, 0) AS NUMBER(38,2))
                     * COALESCE(fx.CURRENT_RATE,   1)
            WHEN a.BS_CATEGORY = 'Equity'
                THEN CAST(COALESCE(tal.AMOUNT, 0) AS NUMBER(38,2))
                     * COALESCE(fx.HISTORICAL_RATE, 1)
            ELSE CAST(COALESCE(tal.AMOUNT,   0) AS NUMBER(38,2))
                 * COALESCE(fx.AVERAGE_RATE,   1)
        END                                                             AS REPORTING_AMOUNT_USD,

        -- FX rates applied (for auditability)
        COALESCE(fx.AVERAGE_RATE,    1)                                 AS FX_AVERAGE_RATE,
        COALESCE(fx.CURRENT_RATE,    1)                                 AS FX_CURRENT_RATE,
        COALESCE(fx.HISTORICAL_RATE, 1)                                 AS FX_HISTORICAL_RATE,

        -- flags
        tal.POSTING                                                     AS IS_POSTING,
        tal."DEFERREVREC"                                               AS IS_DEFERRED_REV_REC,

        tal."_FIVETRAN_SYNCED"                                          AS FIVETRAN_SYNCED_AT

    FROM source tal

    -- only lines from posted, non-voided transactions
    INNER JOIN clean_transactions t
        ON tal."TRANSACTION" = t.TRANSACTION_ID

    -- department, class, location, item context
    LEFT JOIN clean_lines tl
        ON tal."TRANSACTION"     = tl.TRANSACTION_ID
       AND tal."TRANSACTIONLINE" = tl.LINE_ID

    -- account classification and FX rate type
    LEFT JOIN clean_accounts a
        ON tal."ACCOUNT" = a.ACCOUNT_ID

    -- FX rates: match period + subsidiary → USD
    LEFT JOIN fx_rates fx
        ON t.POSTING_PERIOD_ID = fx.PERIOD_ID
       AND t.SUBSIDIARY_ID     = fx.FROM_SUBSIDIARY_ID

    WHERE tal."ACCOUNT" IS NOT NULL

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY tal."TRANSACTION", tal."TRANSACTIONLINE", tal."ACCOUNTINGBOOK"
        ORDER BY tal."_FIVETRAN_SYNCED" DESC
    ) = 1

),

final AS (

    SELECT
        -- surrogate key (composite)
        MD5(
            CAST(TRANSACTION_ID      AS VARCHAR) || '|' ||
            CAST(LINE_ID             AS VARCHAR) || '|' ||
            CAST(ACCOUNTING_BOOK_ID  AS VARCHAR)
        )                                                               AS SURROGATE_KEY,

        joined.*,

        {% if is_incremental() %}
        COALESCE(
            (SELECT MIN(existing.SILVER_CREATED_ON_TS_UTC)
             FROM {{ this }} existing
             WHERE existing.TRANSACTION_ID     = joined.TRANSACTION_ID
               AND existing.LINE_ID            = joined.LINE_ID
               AND existing.ACCOUNTING_BOOK_ID = joined.ACCOUNTING_BOOK_ID),
            CURRENT_TIMESTAMP()
        )                                                               AS SILVER_CREATED_ON_TS_UTC,
        {% else %}
        CURRENT_TIMESTAMP()                                             AS SILVER_CREATED_ON_TS_UTC,
        {% endif %}
        CURRENT_TIMESTAMP()                                             AS SILVER_UPDATED_ON_TS_UTC,
        CAST(NULL AS TIMESTAMP_NTZ)                                     AS SILVER_DELETED_ON_TS_UTC

    FROM joined

)

SELECT * FROM final
