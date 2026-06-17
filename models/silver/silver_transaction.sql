-- Model: silver_transaction
-- Description: Cleaned transaction headers from Bronze RAW.TRANSACTION
-- Grain: One row per transaction (unique TRANSACTION.ID)
-- Key filters:
--   VOID = FALSE       → excludes voided transactions (critical - must never appear in financials)
--   POSTING = TRUE     → only transactions that create GL entries
-- Key fields: TYPE, TRANDATE, POSTINGPERIOD, TOSUBSIDIARY, STATUS, TRANID

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    t.id                                            as transaction_id,
    t.tranid                                        as transaction_ref,
    t.type                                          as transaction_type,
    t.recordtype                                    as record_type,
    cast(t.trandate as date)                        as transaction_date,
    t.postingperiod                                 as posting_period_id,
    t.entity                                        as entity_id,
    t.tosubsidiary                                  as subsidiary_id,  -- fixed: was t.subsidiary
    t.status                                        as status_code,
    ts.status_name                                  as status_name,
    ts.status_full_name                             as status_full_name,
    t.currency                                      as currency_id,
    cast(t.exchangerate as number(38, 9))           as exchange_rate,
    t.memo                                          as memo,
    t.void                                          as is_void,
    t.posting                                       as is_posting,
    t.employee                                      as employee_id,

    -- intercompany fields
    t.intercotransaction                            as interco_transaction_id,
    t.intercostatus                                 as interco_status,
    t.intercoadj                                    as is_interco_adj,

    -- reversal fields
    t.isreversal                                    as is_reversal,
    t.reversal                                      as reversal_transaction_id,
    cast(t.reversaldate as date)                    as reversal_date,

    t._fivetran_synced                              as fivetran_synced_at

from {{ source('raw', 'TRANSACTION') }} t
left join {{ ref('silver_transactionstatus') }} ts
    on t.status    = ts.status_name
    and t.type     = ts.transaction_type

where t.void    = false
  and t.posting = true
  and t._fivetran_deleted = false
