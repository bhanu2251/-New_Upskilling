-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'ITEM_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'reference']
    )
}}

{#
    Model   : item
    Layer   : Silver
    Grain   : 1 row per item (unique ITEM.ID), active items only
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — NULLIF(TRIM()), CAST to NUMBER(38,2) with COALESCE,
              DEDUP via QUALIFY ROW_NUMBER() DESC on _FIVETRAN_SYNCED
    Source  : {{ source('raw', 'ITEM') }}
    Notes   : FIX — QUALIFY dedup added (was missing from all reference tables).
              ISINACTIVE=FALSE filter.
              CLASS, DEPARTMENT, LOCATION, SUBSIDIARY, ITEMID, ITEMTYPE, DISPLAYNAME double-quoted.
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'ITEM') }}
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
        ID                                                              AS ITEM_ID,
        NULLIF(TRIM("ITEMID"), '')                                      AS ITEM_CODE,
        NULLIF(TRIM("DISPLAYNAME"), '')                                 AS DISPLAY_NAME,
        NULLIF(TRIM(DESCRIPTION), '')                                   AS ITEM_DESCRIPTION,
        NULLIF(TRIM("ITEMTYPE"), '')                                    AS ITEM_TYPE,
        "SUBSIDIARY"                                                    AS SUBSIDIARY,
        "DEPARTMENT"                                                    AS DEPARTMENT_ID,
        "CLASS"                                                         AS CLASS_ID,
        "LOCATION"                                                      AS LOCATION_ID,
        "ISINACTIVE"                                                    AS IS_INACTIVE,
        CAST(COALESCE(COST, 0)        AS NUMBER(38,2))                  AS UNIT_COST,
        CAST(COALESCE(AVERAGECOST, 0) AS NUMBER(38,2))                  AS AVERAGE_COST,
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
             WHERE EXISTING.ITEM_ID = RENAMED.ITEM_ID),
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
