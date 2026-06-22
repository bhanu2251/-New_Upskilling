-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'DEPARTMENT_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'reference']
    )
}}

{#
    Model   : department
    Layer   : Silver
    Grain   : 1 row per department (unique DEPARTMENT.ID), active departments only
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — NULLIF(TRIM()) on VARCHAR, ISINACTIVE=FALSE filter,
              DEDUP via QUALIFY ROW_NUMBER() DESC on _FIVETRAN_SYNCED
    Source  : {{ source('raw', 'DEPARTMENT') }}
    Notes   : FIX — QUALIFY dedup added (was missing from all reference tables).
              NAME, FULLNAME, SUBSIDIARY double-quoted.
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'DEPARTMENT') }}
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
        ID                                                              AS DEPARTMENT_ID,
        NULLIF(TRIM("NAME"), '')                                        AS DEPARTMENT_NAME,
        NULLIF(TRIM("FULLNAME"), '')                                    AS DEPARTMENT_FULL_NAME,
        PARENT                                                          AS PARENT_DEPARTMENT_ID,
        "SUBSIDIARY"                                                    AS SUBSIDIARY,
        "ISINACTIVE"                                                    AS IS_INACTIVE,
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
             WHERE EXISTING.DEPARTMENT_ID = RENAMED.DEPARTMENT_ID),
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
