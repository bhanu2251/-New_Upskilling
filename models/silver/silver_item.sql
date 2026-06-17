-- Model: silver_item
-- Description: Cleaned product and service item master from Bronze RAW.ITEM
-- Grain: One row per item (unique ITEM.ID)
-- Key fields: ITEMTYPE, DEPARTMENT, CLASS, SUBSIDIARY
-- Used for COGS analysis by product line

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as item_id,
    itemid                                          as item_code,
    displayname                                     as display_name,
    description                                     as item_description,
    itemtype                                        as item_type,
    subsidiary                                      as subsidiary,
    department                                      as department_id,
    class                                           as class_id,
    location                                        as location_id,
    isinactive                                      as is_inactive,
    cost                                            as unit_cost,
    averagecost                                     as average_cost,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'ITEM') }}
where isinactive = false
