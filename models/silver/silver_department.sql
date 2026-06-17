-- Model: silver_department
-- Description: Cleaned department hierarchy from Bronze RAW.DEPARTMENT
-- Grain: One row per department (unique DEPARTMENT.ID)
-- Key fields: PARENT (multi-level hierarchy e.g. Sales > North America Sales),
--             SUBSIDIARY (department belongs to a specific subsidiary)

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as department_id,
    name                                            as department_name,
    fullname                                        as department_full_name,
    parent                                          as parent_department_id,
    subsidiary                                      as subsidiary,
    isinactive                                      as is_inactive,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'DEPARTMENT') }}
where isinactive = false
