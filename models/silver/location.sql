-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'LOCATION_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'reference']
    )
}}

{#
    Model   : location
    Layer   : Silver
    Grain   : 1 row per location (unique LOCATION.ID), active locations only
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — NULLIF(TRIM()) on VARCHAR, ISINACTIVE=FALSE filter,
              DEDUP via QUALIFY ROW_NUMBER() DESC on _FIVETRAN_SYNCED
    Source  : {{ source('raw', 'Location') }}  — mixed-case source name, quoting in _sources.yml
    Notes   : FIX — QUALIFY dedup added (was missing from all reference tables).
              Source table is 'Location' (mixed case) — handled by quoting: identifier: true in _sources.yml.
              NAME, FULLNAME, SUBSIDIARY, LOCATIONTYPE, MAINADDRESS double-quoted.
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'Location') }}
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
        MD5(CAST(ID AS VARCHAR))                                        AS SURROGATE_KEY,
        ID                                                              AS LOCATION_ID,
        NULLIF(TRIM("NAME"), '')                                        AS LOCATION_NAME,
        NULLIF(TRIM("FULLNAME"), '')                                    AS LOCATION_FULL_NAME,
        PARENT                                                          AS PARENT_LOCATION_ID,
        "SUBSIDIARY"                                                    AS SUBSIDIARY_ID,
        NULLIF(TRIM("LOCATIONTYPE"), '')                                AS LOCATION_TYPE,
        "ISINACTIVE"                                                    AS IS_INACTIVE,
        "MAINADDRESS"                                                   AS MAIN_ADDRESS_ID,
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
             WHERE EXISTING.LOCATION_ID = RENAMED.LOCATION_ID),
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
