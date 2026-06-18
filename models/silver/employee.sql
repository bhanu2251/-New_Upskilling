-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-18T09:52:56Z UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'EMPLOYEE_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'reference']
    )
}}

{#
    Model   : employee
    Layer   : Silver
    Grain   : 1 row per employee (unique EMPLOYEE.ID), active employees only
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — NULLIF(TRIM()) on VARCHAR, boolean filter
    Source  : {{ source('raw', 'EMPLOYEE') }}
    Notes   : ISINACTIVE = FALSE filter.
              ENTITYID, DEPARTMENT, SUBSIDIARY, LOCATION double-quoted.
#}

WITH source AS (

    SELECT *
    FROM {{ source('raw', 'EMPLOYEE') }}
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
        ID                                                              AS EMPLOYEE_ID,
        NULLIF(TRIM("ENTITYID"), '')                                    AS EMPLOYEE_CODE,
        NULLIF(TRIM(FIRSTNAME), '')                                     AS FIRST_NAME,
        NULLIF(TRIM(LASTNAME), '')                                      AS LAST_NAME,
        "DEPARTMENT"                                                    AS DEPARTMENT_ID,
        "SUBSIDIARY"                                                    AS SUBSIDIARY_ID,
        "LOCATION"                                                      AS LOCATION_ID,
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
             WHERE existing.EMPLOYEE_ID = renamed.EMPLOYEE_ID),
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
