-- Model: location
-- Description: Cleaned location master from Bronze RAW.Location (mixed case!)
-- Grain: One row per location (unique LOCATION.ID)
-- Cleaning: trim, nullif, dedup, isinactive filter
-- Reserved words handled: name → location_name
-- NOTE: source table is 'Location' (mixed case) - quoting applied in sources.yml

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'Location') }}   -- mixed case: quoting in sources.yml handles this
),

cleaned as (
    select
        id                                              as location_id,
        nullif(trim(name), '')                          as location_name,        -- name is a reserved word
        nullif(trim(fullname), '')                      as location_full_name,
        parent                                          as parent_location_id,
        subsidiary                                      as subsidiary_id,
        nullif(trim(locationtype), '')                  as location_type,
        isinactive                                      as is_inactive,
        mainaddress                                     as main_address_id,

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
