-- Model: accountingperiod
-- Description: Cleaned fiscal calendar from Bronze RAW.ACCOUNTINGPERIOD
-- Grain: One row per accounting period (unique ACCOUNTINGPERIOD.ID)
-- Cleaning: trim on text, date casts, dedup, isinactive filter
-- Reserved words handled: none in this table

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'ACCOUNTINGPERIOD') }}
),

cleaned as (
    select
        id                                              as period_id,
        nullif(trim(periodname), '')                    as period_name,
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

        -- Derived: fiscal year, quarter, month from start date
        year(cast(startdate as date))                   as fiscal_year,
        quarter(cast(startdate as date))                as fiscal_quarter,
        month(cast(startdate as date))                  as fiscal_month,

        -- Derived: period type label
        case
            when isyear    = true then 'Year'
            when isquarter = true then 'Quarter'
            when isadjust  = true then 'Adjustment'
            else 'Month'
        end                                             as period_type,

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
