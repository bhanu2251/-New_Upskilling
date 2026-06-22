-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-22T UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{{
    config(
        materialized     = 'table',
        schema           = 'SILVER',
        unique_key       = 'ENTITY_ID',
        on_schema_change = 'fail',
        tags             = ['silver', 'netsuite', 'reference']
    )
}}

{#
    Model   : entity
    Layer   : Silver
    Grain   : 1 row per counterparty entity (unique ENTITY.ID), active entities only
    Schema  : static — explicit column list from Silver LLD
    Cleaning: inline — NULLIF(TRIM()) on VARCHAR, ISINACTIVE=FALSE filter,
              DEDUP via QUALIFY ROW_NUMBER() DESC on _FIVETRAN_SYNCED
    Source  : {{ source('raw', 'ENTITY') }}
    Notes   : FIX — QUALIFY dedup added (was missing from all reference tables).
              TYPE, ENTITYNUMBER, ENTITYID, FULLNAME, EMPLOYEE double-quoted (reserved words).
#}

WITH SOURCE AS (

    SELECT *
    FROM {{ source('raw', 'ENTITY') }}
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
        ID                                                              AS ENTITY_ID,
        NULLIF(TRIM("TYPE"), '')                                        AS ENTITY_TYPE,
        NULLIF(TRIM("ENTITYNUMBER"), '')                                AS ENTITY_NUMBER,
        NULLIF(TRIM("ENTITYID"), '')                                    AS ENTITY_CODE,
        NULLIF(TRIM("FULLNAME"), '')                                    AS ENTITY_FULL_NAME,
        NULLIF(TRIM(FIRSTNAME), '')                                     AS FIRST_NAME,
        NULLIF(TRIM(LASTNAME), '')                                      AS LAST_NAME,
        CUSTOMER                                                        AS CUSTOMER_ID,
        VENDOR                                                          AS VENDOR_ID,
        "EMPLOYEE"                                                      AS EMPLOYEE_ID,
        PARENT                                                          AS PARENT_ENTITY_ID,
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
             WHERE EXISTING.ENTITY_ID = RENAMED.ENTITY_ID),
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
