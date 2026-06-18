-- Model: subsidiary
-- Description: Cleaned legal entity hierarchy from Bronze RAW.SUBSIDIARY
-- Grain: One row per subsidiary (unique SUBSIDIARY.ID)
-- Cleaning: trim, nullif, dedup, isinactive filter
-- Reserved words handled: none in this table

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'SUBSIDIARY') }}
),

cleaned as (
    select
        id                                              as subsidiary_id,
        nullif(trim(name), '')                          as subsidiary_name,
        nullif(trim(fullname), '')                      as subsidiary_full_name,
        nullif(trim(legalname), '')                     as legal_name,
        parent                                          as parent_subsidiary_id,
        currency                                        as currency_id,
        nullif(trim(country), '')                       as country,
        iselimination                                   as is_elimination,
        isinactive                                      as is_inactive,
        fiscalcalendar                                  as fiscal_calendar_id,
        intercoaccount                                  as interco_account,
        nullif(trim(federalidnumber), '')               as federal_id_number,

        -- Derived: top-level parent entity (PCP Holdings has no parent)
        case
            when parent is null then true
            else false
        end                                             as is_parent_entity,

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
