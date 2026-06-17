-- Model: silver_consolidatedexchangerate
-- Description: Cleaned period-level FX rates from Bronze RAW.CONSOLIDATEDEXCHANGERATE
-- Grain: One row per period + currency pair + subsidiary combination
-- Key fields:
--   AVERAGERATE   → applied to P&L accounts (Income Statement translation)
--   CURRENTRATE   → applied to Balance Sheet asset/liability accounts (period-end spot rate)
--   HISTORICALRATE → applied to equity balances
-- Essential for ProSport Direct (CAD) and OutdoorEdge Co. (GBP) USD consolidation

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as exchange_rate_id,
    postingperiod                                   as period_id,
    fromcurrency                                    as from_currency_id,
    tocurrency                                      as to_currency_id,
    fromsubsidiary                                  as from_subsidiary_id,
    tosubsidiary                                    as to_subsidiary_id,
    cast(averagerate as number(38, 11))             as average_rate,
    cast(currentrate as number(38, 11))             as current_rate,
    cast(historicalrate as number(38, 11))          as historical_rate,
    iseliminationsubsidiary                         as is_elimination_subsidiary,
    isperiodclosed                                  as is_period_closed,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'CONSOLIDATEDEXCHANGERATE') }}
where _fivetran_deleted = false
