-- Model: silver_accountingperiod
-- Description: Cleaned fiscal calendar from Bronze RAW.ACCOUNTINGPERIOD
-- Grain: One row per accounting period (unique ACCOUNTINGPERIOD.ID)
-- Key fields: ISPOSTING (only posting periods accept journal entries),
--             CLOSED (locked periods), ISADJUST (year-end adjustment periods)

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as period_id,
    periodname                                      as period_name,
    cast(startdate as date)                         as start_date,
    cast(enddate as date)                           as end_date,
    isyear                                          as is_year,
    isquarter                                       as is_quarter,
    isadjust                                        as is_adjust,
    closed                                          as is_closed,
    alllocked                                       as all_locked,
    aplocked                                        as ap_locked,
    arlocked                                        as ar_locked,
    isposting                                       as is_posting,
    isinactive                                      as is_inactive,

    -- Derived: fiscal year extracted from period name or start date
    year(cast(startdate as date))                   as fiscal_year,

    -- Derived: fiscal quarter
    quarter(cast(startdate as date))                as fiscal_quarter,

    -- Derived: fiscal month
    month(cast(startdate as date))                  as fiscal_month,

    -- Derived: period label for reporting
    case
        when isyear    = true then 'Year'
        when isquarter = true then 'Quarter'
        when isadjust  = true then 'Adjustment'
        else 'Month'
    end                                             as period_type,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'ACCOUNTINGPERIOD') }}
where isinactive = false
