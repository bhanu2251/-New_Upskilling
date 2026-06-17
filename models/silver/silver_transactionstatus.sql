-- Model: silver_transactionstatus
-- Description: Lookup table mapping transaction status codes from RAW.TRANSACTIONSTATUS
-- Grain: One row per transaction status (unique TRANSACTION_STATUS_ID)
-- Key fields: TRANSACTION_STATUS_NAME, TRANSACTION_TYPE
-- Used in Silver GL to decode STATUS field on TRANSACTION

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    transaction_status_id                           as transaction_status_id,
    transaction_status_full_name                    as status_full_name,
    transaction_status_name                         as status_name,
    transaction_type                                as transaction_type,
    tran_custom_type_id                             as custom_type_id

from {{ source('raw', 'TRANSACTIONSTATUS') }}
