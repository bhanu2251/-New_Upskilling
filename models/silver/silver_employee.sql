-- Model: silver_employee
-- Description: Cleaned employee master from Bronze RAW.EMPLOYEE
-- Grain: One row per employee (unique EMPLOYEE.ID)
-- Key fields: DEPARTMENT, SUBSIDIARY, LOCATION
-- Used to attribute employee-related GL entries to correct department

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as employee_id,
    entityid                                        as employee_code,
    firstname                                       as first_name,
    lastname                                        as last_name,
    department                                      as department_id,
    subsidiary                                      as subsidiary_id,
    location                                        as location_id,
    isinactive                                      as is_inactive,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'EMPLOYEE') }}
where isinactive = false
