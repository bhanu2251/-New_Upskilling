-- Model: silver_transactionaccountingline
-- Description: The clean General Ledger - most important model in the entire platform
-- Grain: One row per posted accounting line
--        (TRANSACTION + TRANSACTIONLINE + ACCOUNTINGBOOK composite key)
-- Key filters:
--   POSTING = TRUE     → only GL-impacting lines (critical - non-posting lines must be excluded)
--   Join to silver_transaction → excludes voided and non-posting transaction headers
-- FX Translation:
--   functional_amount     → amount in subsidiary's own currency (as posted in NetSuite)
--   reporting_amount_usd  → translated to USD using rate type from ACCOUNT.GENERALRATE:
--                           P&L accounts      → AVERAGERATE
--                           Asset/Liability   → CURRENTRATE
--                           Equity            → HISTORICALRATE

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    -- keys
    tal.transaction                                         as transaction_id,
    tal.transactionline                                     as line_id,
    tal.accountingbook                                      as accounting_book_id,
    tal.account                                             as account_id,

    -- transaction context
    t.transaction_ref                                       as transaction_ref,
    t.transaction_type                                      as transaction_type,
    t.transaction_date                                      as transaction_date,
    t.posting_period_id                                     as period_id,
    t.subsidiary_id                                         as subsidiary_id,
    t.entity_id                                             as entity_id,
    t.currency_id                                           as transaction_currency_id,

    -- line context from transactionline
    tl.department_id                                        as department_id,
    tl.class_id                                             as class_id,
    tl.location_id                                          as location_id,
    tl.item_id                                              as item_id,
    tl.is_cogs                                              as is_cogs,
    tl.eliminate                                            as eliminate,

    -- account context
    a.account_number                                        as account_number,
    a.account_type                                          as account_type,
    a.account_full_name                                     as account_name,
    a.financial_statement                                   as financial_statement,
    a.pl_category                                           as pl_category,
    a.bs_category                                           as bs_category,
    a.cash_flow_rate                                        as cash_flow_rate,
    a.general_rate                                          as general_rate,

    -- debit / credit amounts (functional currency - subsidiary's own currency)
    cast(tal.debit as number(38, 2))                        as debit_amount,
    cast(tal.credit as number(38, 2))                       as credit_amount,
    cast(tal.amount as number(38, 2))                       as amount,
    cast(tal.netamount as number(38, 2))                    as net_amount,

    -- functional amount (in transaction currency as posted)
    cast(tal.amount as number(38, 2))                       as functional_amount,

    -- FX translation to USD
    -- P&L accounts use AVERAGERATE; Balance Sheet assets/liabilities use CURRENTRATE;
    -- Equity uses HISTORICALRATE - per IFRS and US GAAP translation requirements
    case
        when a.financial_statement = 'P&L'
            then cast(tal.amount as number(38, 2))
                 * coalesce(fx.average_rate, 1)
        when a.bs_category in ('Current Asset', 'Non-Current Asset',
                               'Current Liability', 'Non-Current Liability')
            then cast(tal.amount as number(38, 2))
                 * coalesce(fx.current_rate, 1)
        when a.bs_category = 'Equity'
            then cast(tal.amount as number(38, 2))
                 * coalesce(fx.historical_rate, 1)
        else cast(tal.amount as number(38, 2))
             * coalesce(fx.average_rate, 1)
    end                                                     as reporting_amount_usd,

    -- exchange rates applied
    coalesce(fx.average_rate, 1)                            as fx_average_rate,
    coalesce(fx.current_rate, 1)                            as fx_current_rate,
    coalesce(fx.historical_rate, 1)                         as fx_historical_rate,

    -- flags
    tal.posting                                             as is_posting,
    tal.deferrevrec                                         as is_deferred_rev_rec,

    tal._fivetran_synced                                    as fivetran_synced_at

from {{ source('raw', 'TRANSACTIONACCOUNTINGLINE') }} tal

-- join to silver_transaction to enforce void=false and posting=true at header level
inner join {{ ref('silver_transaction') }} t
    on tal.transaction = t.transaction_id

-- join to transactionline for department, class, location context
left join {{ ref('silver_transactionline') }} tl
    on tal.transaction     = tl.transaction_id
    and tal.transactionline = tl.line_id

-- join to account for type classification and FX rate type
left join {{ ref('silver_account') }} a
    on tal.account = a.account_id

-- join to FX rates - match on period + subsidiary currency to USD
left join {{ ref('silver_consolidatedexchangerate') }} fx
    on t.posting_period_id      = fx.period_id
    and t.subsidiary_id         = fx.from_subsidiary_id
    and fx.is_elimination_subsidiary = false

-- critical filter: only posted accounting lines
where tal.posting = true
