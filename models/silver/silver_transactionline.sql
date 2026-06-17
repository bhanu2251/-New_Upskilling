-- Model: silver_transactionline
-- Description: Cleaned line-level transaction detail from Bronze RAW.TRANSACTIONLINE
-- Grain: One row per transaction line (TRANSACTION + ID composite key)
-- Key filters:
--   MAINLINE = FALSE   → excludes header summary lines to avoid double-counting
--   Join to silver_transaction ensures only posted, non-voided lines are included
-- Key fields: DEPARTMENT, CLASS, LOCATION, FOREIGNAMOUNT, AMOUNT, ISCOGS

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    tl.transaction                                  as transaction_id,
    tl.id                                           as line_id,
    tl.department                                   as department_id,
    tl.class                                        as class_id,
    tl.location                                     as location_id,
    tl.entity                                       as entity_id,
    tl.subsidiary                                   as subsidiary_id,
    cast(tl.foreignamount as number(38, 2))         as foreign_amount,
    cast(tl.creditforeignamount as number(38, 2))   as credit_foreign_amount,
    cast(tl.debitforeignamount as number(38, 2))    as debit_foreign_amount,
    cast(tl.netamount as number(38, 2))             as net_amount,
    tl.memo                                         as line_memo,
    tl.mainline                                     as is_mainline,
    tl.iscogs                                       as is_cogs,
    tl.expenseaccount                               as expense_account_id,
    tl.taxline                                      as is_tax_line,
    tl.item                                         as item_id,
    tl.itemtype                                     as item_type,
    tl.eliminate                                    as eliminate,
    tl._fivetran_synced                             as fivetran_synced_at

from {{ source('raw', 'TRANSACTIONLINE') }} tl
-- only include lines from posted, non-voided transactions
inner join {{ ref('silver_transaction') }} t
    on tl.transaction = t.transaction_id

where tl.mainline = false
  and tl.taxline  = false
