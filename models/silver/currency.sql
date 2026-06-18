-- Model: currency
-- Description: Cleaned currency master from Bronze RAW.CURRENCY
-- Grain: One row per currency (unique CURRENCY.ID)
-- Cleaning: trim, nullif, dedup, isinactive filter
-- Reserved words handled: none in this table

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'CURRENCY') }}
),

cleaned as (
    select
        id                                              as currency_id,
        nullif(trim(name), '')                          as currency_name,
        nullif(trim(symbol), '')                        as currency_symbol,
        nullif(trim(displaysymbol), '')                 as display_symbol,
        isbasecurrency                                  as is_base_currency,
        cast(coalesce(exchangerate, 1) as number(38,9)) as exchange_rate,
        isinactive                                      as is_inactive,

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
