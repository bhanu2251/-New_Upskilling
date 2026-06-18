-- Model: entity
-- Description: Cleaned counterparty master from Bronze RAW.ENTITY
-- Grain: One row per entity (unique ENTITY.ID)
-- Cleaning: trim, nullif, dedup, isinactive filter
-- Reserved words handled: type → entity_type (TYPE is a reserved word in Snowflake)

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'ENTITY') }}
),

cleaned as (
    select
        id                                              as entity_id,
        nullif(trim(type), '')                          as entity_type,          -- type is a reserved word
        nullif(trim(entitynumber), '')                  as entity_number,
        nullif(trim(entityid), '')                      as entity_code,
        nullif(trim(fullname), '')                      as entity_full_name,
        nullif(trim(firstname), '')                     as first_name,
        nullif(trim(lastname), '')                      as last_name,
        customer                                        as customer_id,
        vendor                                          as vendor_id,
        employee                                        as employee_id,
        parent                                          as parent_entity_id,
        isinactive                                      as is_inactive,

        _fivetran_synced                                as fivetran_synced_at,

        row_number() over (
            partition by id
            order by _fivetran_synced desc
        )                                               as _row_num

    from source
    where isinactive = false
)

select * exclude (_row_num)
from cleaned
where _row_num = 1
