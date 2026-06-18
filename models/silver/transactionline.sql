-- Model: transactionline
-- Description: Cleaned line-level transaction detail from Bronze RAW.TRANSACTIONLINE
-- Grain: One row per transaction line (TRANSACTION + ID composite key)
-- Cleaning: trim, nullif, numeric casts, dedup
-- Key filters: mainline=false (no header summary lines), taxline=false, inner join to transaction
-- Reserved words handled:
--   class → class_id  (CLASS is reserved in Snowflake)

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'TRANSACTIONLINE') }}
),

cleaned as (
    select
        tl.transaction                                  as transaction_id,
        tl.id                                           as line_id,
        tl.department                                   as department_id,
        tl.class                                        as class_id,             -- class is a reserved word
        tl.location                                     as location_id,
        tl.entity                                       as entity_id,
        tl.subsidiary                                   as subsidiary_id,
        cast(coalesce(tl.foreignamount, 0) as number(38, 2))       as foreign_amount,
        cast(coalesce(tl.creditforeignamount, 0) as number(38, 2)) as credit_foreign_amount,
        cast(coalesce(tl.debitforeignamount, 0) as number(38, 2))  as debit_foreign_amount,
        cast(coalesce(tl.netamount, 0) as number(38, 2))            as net_amount,
        nullif(trim(tl.memo), '')                       as line_memo,
        tl.mainline                                     as is_mainline,
        tl.iscogs                                       as is_cogs,
        tl.expenseaccount                               as expense_account_id,
        tl.taxline                                      as is_tax_line,
        tl.item                                         as item_id,
        nullif(trim(tl.itemtype), '')                   as item_type,
        tl.eliminate                                    as eliminate,

        tl._fivetran_synced                             as fivetran_synced_at,

        row_number() over (
            partition by tl.transaction, tl.id
            order by tl._fivetran_synced desc
        )                                               as _row_num

    from source tl
    -- inner join ensures only lines from posted, non-voided transactions pass through
    inner join {{ ref('transaction') }} t
        on tl.transaction = t.transaction_id

    where tl.mainline = false
      and tl.taxline  = false
)

select * exclude (_row_num)
from cleaned
where _row_num = 1
