-- Model: silver_location
-- Description: Cleaned location master from Bronze RAW.LOCATION
-- Grain: One row per location (unique LOCATION.ID)
-- Key fields: PARENT (location hierarchy), SUBSIDIARY, LOCATIONTYPE

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as location_id,
    name                                            as location_name,
    fullname                                        as location_full_name,
    parent                                          as parent_location_id,
    subsidiary                                      as subsidiary_id,
    locationtype                                    as location_type,
    isinactive                                      as is_inactive,
    mainaddress                                     as main_address_id,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'LOCATION') }}
where isinactive = false
