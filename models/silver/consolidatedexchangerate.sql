-- Model: consolidatedexchangerate
-- Description: Cleaned period-level FX rates from Bronze RAW.CONSOLIDATEDEXCHANGERATE
-- Grain: One row per period + from_subsidiary + to_currency combination
-- Cleaning: numeric casts, coalesce on rates, dedup, _fivetran_deleted filter
-- Reserved words handled: none in this table
-- Critical: AVERAGERATE → P&L, CURRENTRATE → BS assets/liabilities, HISTORICALRATE → equity

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'CONSOLIDATEDEXCHANGERATE') }}
),

cleaned as (
    select
        id                                                  as exchange_rate_id,
        postingperiod                                       as period_id,
        fromcurrency                                        as from_currency_id,
        tocurrency                                          as to_currency_id,
        fromsubsidiary                                      as from_subsidiary_id,
        tosubsidiary                                        as to_subsidiary_id,
        -- coalesce to 1 (no conversion) if rate is missing — safe default for USD→USD rows
        cast(coalesce(averagerate, 1) as number(38, 11))    as average_rate,
        cast(coalesce(currentrate, 1) as number(38, 11))    as current_rate,
        cast(coalesce(historicalrate, 1) as number(38, 11)) as historical_rate,
        iseliminationsubsidiary                             as is_elimination_subsidiary,
        isperiodclosed                                      as is_period_closed,

        _fivetran_synced                                    as fivetran_synced_at,

        row_number() over (
            partition by postingperiod, fromsubsidiary, tocurrency
            order by _fivetran_synced desc
        )                                                   as _row_num

    from source
    where _fivetran_deleted = false
)

select * exclude (_row_num)
from cleaned
where _row_num = 1
