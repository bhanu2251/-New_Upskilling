-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'PERIOD_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'reference']
    )
}}

{#
    Model   : accountingperiod
    Layer   : Silver
    Grain   : 1 row per fiscal period (unique ACCOUNTINGPERIOD.ID), active periods only
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — CAST(x AS DATE), boolean pass-through, derived fiscal fields,
              DEDUP via QUALIFY ROW_NUMBER() DESC on _FIVETRAN_SYNCED
    Source  : {{ source('raw', 'ACCOUNTINGPERIOD') }}
    Notes   : FIX — QUALIFY dedup added (was missing from all reference tables).
              ISINACTIVE=FALSE filter applied.
              Derived: FISCAL_YEAR, FISCAL_QUARTER, FISCAL_MONTH, PERIOD_TYPE.
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'ACCOUNTINGPERIOD') }}
    {% if is_incremental() %}
    WHERE "_FIVETRAN_SYNCED" > (SELECT MAX(SILVER_UPDATED_ON_TS_UTC) FROM {{ this }})
    {% endif %}

),

CLEANED AS (

    SELECT *
    FROM SOURCE
    WHERE "ISINACTIVE" = FALSE

),

RENAMED AS (

    SELECT
        -- surrogate key
        MD5(CAST(ID AS VARCHAR))                                        AS SURROGATE_KEY,

        -- primary key
        ID                                                              AS PERIOD_ID,

        -- attributes
        NULLIF(TRIM("PERIODNAME"), '')                                  AS PERIOD_NAME,
        CAST("STARTDATE" AS DATE)                                       AS START_DATE,
        CAST("ENDDATE" AS DATE)                                         AS END_DATE,
        "ISYEAR"                                                        AS IS_YEAR,
        "ISQUARTER"                                                     AS IS_QUARTER,
        "ISADJUST"                                                      AS IS_ADJUST,
        CLOSED                                                          AS IS_CLOSED,
        "ALLLOCKED"                                                     AS ALL_LOCKED,
        "APLOCKED"                                                      AS AP_LOCKED,
        "ARLOCKED"                                                      AS AR_LOCKED,
        "ISPOSTING"                                                     AS IS_POSTING,
        "ISINACTIVE"                                                    AS IS_INACTIVE,

        -- derived fiscal fields
        YEAR(CAST("STARTDATE" AS DATE))                                 AS FISCAL_YEAR,
        QUARTER(CAST("STARTDATE" AS DATE))                              AS FISCAL_QUARTER,
        MONTH(CAST("STARTDATE" AS DATE))                                AS FISCAL_MONTH,

        -- derived period type
        CASE
            WHEN "ISYEAR"    = TRUE THEN 'Year'
            WHEN "ISQUARTER" = TRUE THEN 'Quarter'
            WHEN "ISADJUST"  = TRUE THEN 'Adjustment'
            ELSE 'Month'
        END                                                             AS PERIOD_TYPE,

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
             WHERE EXISTING.PERIOD_ID = RENAMED.PERIOD_ID),
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
