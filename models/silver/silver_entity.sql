-- Model: silver_entity
-- Description: Cleaned counterparty master from Bronze RAW.ENTITY
-- Grain: One row per entity (unique ENTITY.ID)
-- Key fields: TYPE (Customer, Vendor, Employee, Partner),
--             Used to identify counterparty on TRANSACTION

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as entity_id,
    type                                            as entity_type,
    entitynumber                                    as entity_number,
    entityid                                        as entity_code,
    fullname                                        as entity_full_name,
    firstname                                       as first_name,
    lastname                                        as last_name,
    customer                                        as customer_id,
    vendor                                          as vendor_id,
    employee                                        as employee_id,
    parent                                          as parent_entity_id,
    isinactive                                      as is_inactive,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'ENTITY') }}
where isinactive = false
