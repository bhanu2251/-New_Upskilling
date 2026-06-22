-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'EXCHANGE_RATE_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'fx']
    )
}}

{#
    Model   : consolidatedexchangerate
    Layer   : Silver
    Grain   : 1 row per period + from_subsidiary + to_currency combination
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — CAST to NUMBER(38,11) with COALESCE, boolean pass-through,
              DEDUP via QUALIFY ROW_NUMBER() DESC on _FIVETRAN_SYNCED
    Source  : {{ source('raw', 'CONSOLIDATEDEXCHANGERATE') }}
    Notes   : FIX — QUALIFY dedup added (was missing from all reference tables).
              _FIVETRAN_DELETED=FALSE filter applied.
              AVERAGERATE → P&L, CURRENTRATE → BS assets/liabilities, HISTORICALRATE → equity.
              All FX-specific Bronze columns double-quoted (camelCase Fivetran names).
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'CONSOLIDATEDEXCHANGERATE') }}
    {% if is_incremental() %}
    WHERE "_FIVETRAN_SYNCED" > (SELECT MAX(SILVER_UPDATED_ON_TS_UTC) FROM {{ this }})
    {% endif %}

),

CLEANED AS (

    SELECT *
    FROM SOURCE
    WHERE _FIVETRAN_DELETED = FALSE

),

RENAMED AS (

    SELECT
        MD5(CAST(ID AS VARCHAR))                                        AS SURROGATE_KEY,
        ID                                                              AS EXCHANGE_RATE_ID,
        "POSTINGPERIOD"                                                 AS PERIOD_ID,
        "FROMCURRENCY"                                                  AS FROM_CURRENCY_ID,
        "TOCURRENCY"                                                    AS TO_CURRENCY_ID,
        "FROMSUBSIDIARY"                                                AS FROM_SUBSIDIARY_ID,
        "TOSUBSIDIARY"                                                  AS TO_SUBSIDIARY_ID,
        CAST(COALESCE("AVERAGERATE",    1) AS NUMBER(38,11))            AS AVERAGE_RATE,
        CAST(COALESCE("CURRENTRATE",    1) AS NUMBER(38,11))            AS CURRENT_RATE,
        CAST(COALESCE("HISTORICALRATE", 1) AS NUMBER(38,11))            AS HISTORICAL_RATE,
        "ISELIMINATIONSUBSIDIARY"                                       AS IS_ELIMINATION_SUBSIDIARY,
        "ISPERIODCLOSED"                                                AS IS_PERIOD_CLOSED,
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
             WHERE EXISTING.EXCHANGE_RATE_ID = RENAMED.EXCHANGE_RATE_ID),
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
