{{ config(materialized='view') }}

select *
from {{ source('raw', 'TRANSACTIONACCOUNTINGLINE') }}
