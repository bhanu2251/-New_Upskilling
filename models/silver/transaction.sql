-- Model: transaction
-- Description: Cleaned transaction headers from Bronze RAW.TRANSACTION
-- Grain: One row per transaction (unique TRANSACTION.ID)
-- Cleaning: trim, nullif, date/numeric casts, dedup, void+posting+fivetran_deleted filter
-- Reserved words handled:
--   type   → transaction_type  (TYPE is reserved in Snowflake)
--   status → status_code       (STATUS is reserved in some SQL dialects)

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'TRANSACTION') }}
),

cleaned as (
    select
        t.id                                            as transaction_id,
        nullif(trim(t.tranid), '')                      as transaction_ref,
        nullif(trim(t.type), '')                        as transaction_type,     -- type is a reserved word
        nullif(trim(t.recordtype), '')                  as record_type,
        cast(t.trandate as date)                        as transaction_date,
        t.postingperiod                                 as posting_period_id,
        t.entity                                        as entity_id,
        t.tosubsidiary                                  as subsidiary_id,        -- NOTE: not t.subsidiary
        nullif(trim(t.status), '')                      as status_code,          -- status is a reserved word
        ts.status_name                                  as status_name,
        ts.status_full_name                             as status_full_name,
        t.currency                                      as currency_id,
        cast(coalesce(t.exchangerate, 1) as number(38, 9)) as exchange_rate,
        nullif(trim(t.memo), '')                        as memo,
        t.void                                          as is_void,
        t.posting                                       as is_posting,
        t.employee                                      as employee_id,

        -- intercompany fields
        t.intercotransaction                            as interco_transaction_id,
        nullif(trim(t.intercostatus), '')               as interco_status,
        t.intercoadj                                    as is_interco_adj,

        -- reversal fields
        t.isreversal                                    as is_reversal,
        t.reversal                                      as reversal_transaction_id,
        cast(t.reversaldate as date)                    as reversal_date,

        t._fivetran_synced                              as fivetran_synced_at,

        row_number() over (
            partition by t.id
            order by t._fivetran_synced desc
        )                                               as _row_num

    from source t
    left join {{ ref('transactionstatus') }} ts
        on nullif(trim(t.status), '') = ts.status_name
        and nullif(trim(t.type), '')  = ts.transaction_type

    where t.void             = false
      and t.posting          = true
      and t._fivetran_deleted = false
)

select * exclude (_row_num)
from cleaned
where _row_num = 1
