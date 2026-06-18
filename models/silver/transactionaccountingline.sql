-- Model: transactionaccountingline
-- Description: The clean General Ledger — single source of truth for all financial statements
-- Grain: One row per posted accounting line (TRANSACTION + TRANSACTIONLINE + ACCOUNTINGBOOK)
-- Cleaning: numeric casts, coalesce on amounts/rates, dedup
-- Key filters: posting=true; void/non-posting excluded via inner join to transaction
-- Reserved words handled: none (all column aliases are safe)
-- FX Translation:
--   P&L accounts          → AVERAGERATE
--   Asset / Liability     → CURRENTRATE
--   Equity                → HISTORICALRATE

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'TRANSACTIONACCOUNTINGLINE') }}
),

cleaned as (
    select
        -- keys
        tal.transaction                                         as transaction_id,
        tal.transactionline                                     as line_id,
        tal.accountingbook                                      as accounting_book_id,
        tal.account                                             as account_id,

        -- transaction context (from silver transaction — already clean)
        t.transaction_ref                                       as transaction_ref,
        t.transaction_type                                      as transaction_type,
        t.transaction_date                                      as transaction_date,
        t.posting_period_id                                     as period_id,
        t.subsidiary_id                                         as subsidiary_id,
        t.entity_id                                             as entity_id,
        t.currency_id                                           as transaction_currency_id,

        -- line context (from silver transactionline — already clean)
        tl.department_id                                        as department_id,
        tl.class_id                                             as class_id,
        tl.location_id                                          as location_id,
        tl.item_id                                              as item_id,
        tl.is_cogs                                              as is_cogs,
        tl.eliminate                                            as eliminate,

        -- account context (from silver account — already clean)
        a.account_number                                        as account_number,
        a.account_type                                          as account_type,
        a.account_full_name                                     as account_name,
        a.financial_statement                                   as financial_statement,
        a.pl_category                                           as pl_category,
        a.bs_category                                           as bs_category,
        a.cash_flow_rate                                        as cash_flow_rate,
        a.general_rate                                          as general_rate,

        -- debit / credit / net amounts (functional currency)
        cast(coalesce(tal.debit, 0) as number(38, 2))           as debit_amount,
        cast(coalesce(tal.credit, 0) as number(38, 2))          as credit_amount,
        cast(coalesce(tal.amount, 0) as number(38, 2))          as amount,
        cast(coalesce(tal.netamount, 0) as number(38, 2))       as net_amount,
        cast(coalesce(tal.amount, 0) as number(38, 2))          as functional_amount,

        -- FX translation to USD
        -- P&L → AVERAGERATE; BS Assets/Liabilities → CURRENTRATE; Equity → HISTORICALRATE
        case
            when a.financial_statement = 'P&L'
                then cast(coalesce(tal.amount, 0) as number(38, 2))
                     * coalesce(fx.average_rate, 1)
            when a.bs_category in ('Current Asset', 'Non-Current Asset',
                                   'Current Liability', 'Non-Current Liability')
                then cast(coalesce(tal.amount, 0) as number(38, 2))
                     * coalesce(fx.current_rate, 1)
            when a.bs_category = 'Equity'
                then cast(coalesce(tal.amount, 0) as number(38, 2))
                     * coalesce(fx.historical_rate, 1)
            else cast(coalesce(tal.amount, 0) as number(38, 2))
                 * coalesce(fx.average_rate, 1)
        end                                                     as reporting_amount_usd,

        -- exchange rates applied (for auditability)
        coalesce(fx.average_rate, 1)                            as fx_average_rate,
        coalesce(fx.current_rate, 1)                            as fx_current_rate,
        coalesce(fx.historical_rate, 1)                         as fx_historical_rate,

        -- flags
        tal.posting                                             as is_posting,
        tal.deferrevrec                                         as is_deferred_rev_rec,

        tal._fivetran_synced                                    as fivetran_synced_at,

        row_number() over (
            partition by tal.transaction, tal.transactionline, tal.accountingbook
            order by tal._fivetran_synced desc
        )                                                       as _row_num

    from source tal

    -- enforces void=false and posting=true at header level
    inner join {{ ref('transaction') }} t
        on tal.transaction = t.transaction_id

    -- department, class, location context
    left join {{ ref('transactionline') }} tl
        on tal.transaction      = tl.transaction_id
        and tal.transactionline = tl.line_id

    -- account classification and FX rate type
    left join {{ ref('account') }} a
        on tal.account = a.account_id

    -- FX rates: match period + from_subsidiary → USD, exclude elimination subsidiaries
    left join {{ ref('consolidatedexchangerate') }} fx
        on t.posting_period_id          = fx.period_id
        and t.subsidiary_id             = fx.from_subsidiary_id
        and fx.is_elimination_subsidiary = false

    -- only posted GL lines
    where tal.posting = true
)

select * exclude (_row_num)
from cleaned
where _row_num = 1
