-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'ACCOUNT_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'reference']
    )
}}

{#
    Model   : account
    Layer   : Silver
    Grain   : 1 row per NetSuite account (unique ACCOUNT.ID), active accounts only
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — NULLIF(TRIM()) on VARCHAR, CAST on DATE, ISINACTIVE=FALSE filter,
              DEDUP via QUALIFY ROW_NUMBER() DESC on _FIVETRAN_SYNCED
    Source  : {{ source('raw', 'ACCOUNT') }}
    Notes   : FIX — QUALIFY dedup added (was missing from all reference tables).
              Derived cols: FINANCIAL_STATEMENT, PL_CATEGORY, BS_CATEGORY from ACCTTYPE.
              Reserved-word Bronze columns double-quoted throughout.
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'ACCOUNT') }}
    {% if is_incremental() %}
    WHERE "_FIVETRAN_SYNCED" > (SELECT MAX(SILVER_UPDATED_ON_TS_UTC) FROM {{ this }})
    {% endif %}

),

CLEANED AS (

    SELECT *
    FROM SOURCE
    WHERE ISINACTIVE = FALSE

),

RENAMED AS (

    SELECT
        -- surrogate key
        MD5(CAST(ID AS VARCHAR))                                        AS SURROGATE_KEY,

        -- primary key
        ID                                                              AS ACCOUNT_ID,

        -- attributes
        NULLIF(TRIM("ACCTNUMBER"), '')                                  AS ACCOUNT_NUMBER,
        NULLIF(TRIM("ACCTTYPE"), '')                                    AS ACCOUNT_TYPE,
        NULLIF(TRIM("FULLNAME"), '')                                    AS ACCOUNT_FULL_NAME,
        NULLIF(TRIM("DISPLAYNAMEWITHHIERARCHY"), '')                    AS ACCOUNT_DISPLAY_NAME,
        PARENT                                                          AS PARENT_ACCOUNT_ID,
        "SUBSIDIARY"                                                    AS SUBSIDIARY,
        NULLIF(TRIM("CASHFLOWRATE"), '')                                AS CASH_FLOW_RATE,
        NULLIF(TRIM("GENERALRATE"), '')                                 AS GENERAL_RATE,
        "ISSUMMARY"                                                     AS IS_SUMMARY,
        "ISINACTIVE"                                                    AS IS_INACTIVE,
        ELIMINATE                                                       AS ELIMINATE,
        NULLIF(TRIM(DESCRIPTION), '')                                   AS ACCOUNT_DESCRIPTION,

        -- derived: financial statement classification
        CASE
            WHEN TRIM("ACCTTYPE") IN ('Income', 'Other Income',
                 'Cost of Goods Sold', 'Expense', 'Other Expense')          THEN 'P&L'
            WHEN TRIM("ACCTTYPE") IN ('Bank', 'Accounts Receivable',
                 'Other Current Asset', 'Fixed Asset', 'Other Asset',
                 'Deferred Expense', 'Accounts Payable',
                 'Other Current Liability', 'Long Term Liability',
                 'Deferred Revenue', 'Equity', 'Retained Earnings')         THEN 'Balance Sheet'
            ELSE 'Unclassified'
        END                                                             AS FINANCIAL_STATEMENT,

        -- derived: P&L sub-category
        CASE
            WHEN TRIM("ACCTTYPE") IN ('Income', 'Other Income')             THEN 'Revenue'
            WHEN TRIM("ACCTTYPE") = 'Cost of Goods Sold'                    THEN 'COGS'
            WHEN TRIM("ACCTTYPE") IN ('Expense', 'Other Expense')           THEN 'Operating Expense'
            ELSE NULL
        END                                                             AS PL_CATEGORY,

        -- derived: balance sheet sub-category
        CASE
            WHEN TRIM("ACCTTYPE") IN ('Bank', 'Accounts Receivable',
                 'Other Current Asset')                                     THEN 'Current Asset'
            WHEN TRIM("ACCTTYPE") IN ('Fixed Asset', 'Other Asset',
                 'Deferred Expense')                                        THEN 'Non-Current Asset'
            WHEN TRIM("ACCTTYPE") IN ('Accounts Payable',
                 'Other Current Liability', 'Deferred Revenue')             THEN 'Current Liability'
            WHEN TRIM("ACCTTYPE") = 'Long Term Liability'                   THEN 'Non-Current Liability'
            WHEN TRIM("ACCTTYPE") IN ('Equity', 'Retained Earnings')        THEN 'Equity'
            ELSE NULL
        END                                                             AS BS_CATEGORY,

        "_FIVETRAN_SYNCED"                                              AS FIVETRAN_SYNCED_AT

    FROM CLEANED

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ID
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
             WHERE EXISTING.ACCOUNT_ID = RENAMED.ACCOUNT_ID),
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
