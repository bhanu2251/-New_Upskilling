-- Model: silver_classification
-- Description: Cleaned business line / class segments from Bronze RAW.CLASSIFICATION
-- Grain: One row per classification (unique CLASSIFICATION.ID)
-- Key fields: PARENT (two-level hierarchy), SUBSIDIARY

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as class_id,
    name                                            as class_name,
    fullname                                        as class_full_name,
    parent                                          as parent_class_id,
    subsidiary                                      as subsidiary,
    isinactive                                      as is_inactive,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'CLASSIFICATION') }}
where isinactive = false
