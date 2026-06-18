-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-18T09:52:56Z UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'CURRENCY_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'reference']
    )
}}

{#
    Model   : currency
    Layer   : Silver
    Grain   : 1 row per currency (unique CURRENCY.ID), active currencies only
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — NULLIF(TRIM()), CAST to NUMBER(38,9) with COALESCE
    Source  : {{ source('raw', 'CURRENCY') }}
    Notes   : ISINACTIVE = FALSE filter. NAME double-quoted (reserved word).
#}

WITH source AS (

    SELECT *
    FROM {{ source('raw', 'CURRENCY') }}
    {% if is_incremental() %}
    WHERE "_FIVETRAN_SYNCED" > (SELECT MAX(SILVER_UPDATED_ON_TS_UTC) FROM {{ this }})
    {% endif %}

),

cleaned AS (

    SELECT *
    FROM source
    WHERE "ISINACTIVE" = FALSE

),

renamed AS (

    SELECT
        MD5(CAST(ID AS VARCHAR))                                        AS SURROGATE_KEY,
        ID                                                              AS CURRENCY_ID,
        NULLIF(TRIM("NAME"), '')                                        AS CURRENCY_NAME,
        NULLIF(TRIM(SYMBOL), '')                                        AS CURRENCY_SYMBOL,
        NULLIF(TRIM("DISPLAYSYMBOL"), '')                               AS DISPLAY_SYMBOL,
        "ISBASECURRENCY"                                                AS IS_BASE_CURRENCY,
        CAST(COALESCE("EXCHANGERATE", 1) AS NUMBER(38,9))               AS EXCHANGE_RATE,
        "ISINACTIVE"                                                    AS IS_INACTIVE,
        "_FIVETRAN_SYNCED"                                              AS FIVETRAN_SYNCED_AT

    FROM cleaned

),

final AS (

    SELECT
        renamed.*,
        {% if is_incremental() %}
        COALESCE(
            (SELECT MIN(existing.SILVER_CREATED_ON_TS_UTC)
             FROM {{ this }} existing
             WHERE existing.CURRENCY_ID = renamed.CURRENCY_ID),
            CURRENT_TIMESTAMP()
        )                                                               AS SILVER_CREATED_ON_TS_UTC,
        {% else %}
        CURRENT_TIMESTAMP()                                             AS SILVER_CREATED_ON_TS_UTC,
        {% endif %}
        CURRENT_TIMESTAMP()                                             AS SILVER_UPDATED_ON_TS_UTC,
        CAST(NULL AS TIMESTAMP_NTZ)                                     AS SILVER_DELETED_ON_TS_UTC

    FROM renamed

)

SELECT * FROM final
