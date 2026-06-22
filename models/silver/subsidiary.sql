-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-18T09:52:56Z UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'SUBSIDIARY_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'reference']
    )
}}

{#
    Model   : subsidiary
    Layer   : Silver
    Grain   : 1 row per subsidiary / legal entity (unique SUBSIDIARY.ID), active only
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — NULLIF(TRIM()) on VARCHAR, boolean filter, derived IS_PARENT_ENTITY
    Source  : {{ source('raw', 'SUBSIDIARY') }}
    Notes   : ISINACTIVE = FALSE filter.
              NAME, FULLNAME, LEGALNAME, CURRENCY, ISELIMINATION, ISINACTIVE,
              FISCALCALENDAR, INTERCOACCOUNT, FEDERALIDNUMBER double-quoted.
#}

WITH source AS (

    SELECT *
    FROM {{ source('raw', 'SUBSIDIARY') }}
    {% if is_incremental() %}
    WHERE "_FIVETRAN_SYNCED" > (SELECT MAX(SILVER_UPDATED_ON_TS_UTC) FROM {{ this }})
    {% endif %}

),

cleaned AS (

    SELECT *
    FROM source
   -- WHERE "ISINACTIVE" = FALSE

),

renamed AS (

    SELECT
        MD5(CAST(ID AS VARCHAR))                                        AS SURROGATE_KEY,
        ID                                                              AS SUBSIDIARY_ID,
        NULLIF(TRIM("NAME"), '')                                        AS SUBSIDIARY_NAME,
        NULLIF(TRIM("FULLNAME"), '')                                    AS SUBSIDIARY_FULL_NAME,
        NULLIF(TRIM("LEGALNAME"), '')                                   AS LEGAL_NAME,
        PARENT                                                          AS PARENT_SUBSIDIARY_ID,
        "CURRENCY"                                                      AS CURRENCY_ID,
        NULLIF(TRIM(COUNTRY), '')                                       AS COUNTRY,
        "ISELIMINATION"                                                 AS IS_ELIMINATION,
        "ISINACTIVE"                                                    AS IS_INACTIVE,
        "FISCALCALENDAR"                                                AS FISCAL_CALENDAR_ID,
        "INTERCOACCOUNT"                                                AS INTERCO_ACCOUNT,
        NULLIF(TRIM("FEDERALIDNUMBER"), '')                             AS FEDERAL_ID_NUMBER,

        -- derived: top-level parent entity flag
        CASE WHEN PARENT IS NULL THEN TRUE ELSE FALSE END               AS IS_PARENT_ENTITY,

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
             WHERE existing.SUBSIDIARY_ID = renamed.SUBSIDIARY_ID),
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
