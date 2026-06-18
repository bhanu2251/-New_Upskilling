-- Model: employee
-- Description: Cleaned employee master from Bronze RAW.EMPLOYEE
-- Grain: One row per employee (unique EMPLOYEE.ID)
-- Cleaning: trim, nullif, dedup, isinactive filter
-- Reserved words handled: none in this table

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'EMPLOYEE') }}
),

cleaned as (
    select
        id                                              as employee_id,
        nullif(trim(entityid), '')                      as employee_code,
        nullif(trim(firstname), '')                     as first_name,
        nullif(trim(lastname), '')                      as last_name,
        department                                      as department_id,
        subsidiary                                      as subsidiary_id,
        location                                        as location_id,
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
