-- Model: silver_currency
-- Description: Cleaned currency master from Bronze RAW.CURRENCY
-- Grain: One row per currency (unique CURRENCY.ID)
-- Key fields: ISBASECURRENCY (identifies USD as group reporting currency),
--             SYMBOL (used for labelling amounts in financial views)

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as currency_id,
    name                                            as currency_name,
    symbol                                          as currency_symbol,
    displaysymbol                                   as display_symbol,
    isbasecurrency                                  as is_base_currency,
    exchangerate                                    as exchange_rate,
    isinactive                                      as is_inactive,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'CURRENCY') }}
where isinactive = false
