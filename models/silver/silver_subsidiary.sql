-- Model: silver_subsidiary
-- Description: Cleaned legal entity hierarchy from Bronze RAW.SUBSIDIARY
-- Grain: One row per subsidiary (unique SUBSIDIARY.ID)
-- Key fields: PARENT (consolidation tree - all five subsidiaries roll up to PCP Holdings),
--             ISELIMINATION (flags elimination subsidiary for intercompany netting),
--             CURRENCY (functional currency of subsidiary)

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as subsidiary_id,
    name                                            as subsidiary_name,
    fullname                                        as subsidiary_full_name,
    legalname                                       as legal_name,
    parent                                          as parent_subsidiary_id,
    currency                                        as currency_id,
    country                                         as country,
    iselimination                                   as is_elimination,
    isinactive                                      as is_inactive,
    fiscalcalendar                                  as fiscal_calendar_id,
    intercoaccount                                  as interco_account,
    federalidnumber                                 as federal_id_number,

    -- Derived: is this a top-level parent (PCP Holdings)?
    case
        when parent is null then true
        else false
    end                                             as is_parent_entity,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'SUBSIDIARY') }}
where isinactive = false
