-- Model: classification
-- Description: Cleaned business line / class segments from Bronze RAW.CLASSIFICATION
-- Grain: One row per classification (unique CLASSIFICATION.ID)
-- Cleaning: trim, nullif, dedup, isinactive filter
-- Reserved words handled: name → class_name

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'CLASSIFICATION') }}
),

cleaned as (
    select
        id                                              as class_id,
        nullif(trim(name), '')                          as class_name,           -- name is a reserved word
        nullif(trim(fullname), '')                      as class_full_name,
        parent                                          as parent_class_id,
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
