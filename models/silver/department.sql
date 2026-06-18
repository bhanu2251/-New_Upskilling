-- Model: department
-- Description: Cleaned department hierarchy from Bronze RAW.DEPARTMENT
-- Grain: One row per department (unique DEPARTMENT.ID)
-- Cleaning: trim, nullif, dedup, isinactive filter
-- Reserved words handled: name → department_name (NAME is reserved in some SQL dialects)

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'DEPARTMENT') }}
),

cleaned as (
    select
        id                                              as department_id,
        nullif(trim(name), '')                          as department_name,      -- name is a reserved word
        nullif(trim(fullname), '')                      as department_full_name,
        parent                                          as parent_department_id,
        subsidiary                                      as subsidiary,
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
