-- Model: transactionstatus
-- Description: Lookup table for transaction status codes from RAW.TRANSACTIONSTATUS
-- Grain: One row per transaction status (unique TRANSACTION_STATUS_ID)
-- Cleaning: trim, nullif, dedup (no isinactive filter — this is a pure lookup table)
-- Reserved words handled: none in this table

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'TRANSACTIONSTATUS') }}
),

cleaned as (
    select
        transaction_status_id                           as transaction_status_id,
        nullif(trim(transaction_status_full_name), '')  as status_full_name,
        nullif(trim(transaction_status_name), '')       as status_name,
        nullif(trim(transaction_type), '')              as transaction_type,
        nullif(trim(tran_custom_type_id), '')           as custom_type_id,

        row_number() over (
            partition by transaction_status_id
            order by transaction_status_id
        )                                               as _row_num

    from source
)

select * exclude (_row_num)
from cleaned
where _row_num = 1
