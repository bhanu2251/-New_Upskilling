-- Model: item
-- Description: Cleaned product and service item master from Bronze RAW.ITEM
-- Grain: One row per item (unique ITEM.ID)
-- Cleaning: trim, nullif, numeric cast, dedup, isinactive filter
-- Reserved words handled: class → class_id (CLASS is reserved in Snowflake)

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'ITEM') }}
),

cleaned as (
    select
        id                                              as item_id,
        nullif(trim(itemid), '')                        as item_code,
        nullif(trim(displayname), '')                   as display_name,
        nullif(trim(description), '')                   as item_description,
        nullif(trim(itemtype), '')                      as item_type,
        subsidiary                                      as subsidiary,
        department                                      as department_id,
        class                                           as class_id,             -- class is a reserved word
        location                                        as location_id,
        isinactive                                      as is_inactive,
        cast(coalesce(cost, 0) as number(38, 2))        as unit_cost,
        cast(coalesce(averagecost, 0) as number(38, 2)) as average_cost,

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
