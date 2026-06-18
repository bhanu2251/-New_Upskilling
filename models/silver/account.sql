-- Model: account
-- Description: Cleaned Chart of Accounts from Bronze RAW.ACCOUNT
-- Grain: One row per account (unique ACCOUNT.ID)
-- Cleaning: trim on text, nullif on empty strings, dedup via qualify, isinactive filter
-- Reserved words handled: none in this table

{{ config(
    materialized='table',
    schema='SILVER'
) }}

with source as (
    select * from {{ source('raw', 'ACCOUNT') }}
),

cleaned as (
    select
        id                                                          as account_id,
        trim(acctnumber)                                            as account_number,
        trim(accttype)                                              as account_type,
        nullif(trim(fullname), '')                                  as account_full_name,
        nullif(trim(displaynamewithhierarchy), '')                  as account_display_name,
        parent                                                      as parent_account_id,
        subsidiary                                                  as subsidiary,
        nullif(trim(cashflowrate), '')                              as cash_flow_rate,
        nullif(trim(generalrate), '')                               as general_rate,
        issummary                                                   as is_summary,
        isinactive                                                  as is_inactive,
        eliminate                                                   as eliminate,
        nullif(trim(description), '')                               as account_description,

        -- Derived: financial statement classification
        case
            when trim(accttype) in ('Income', 'Other Income')                          then 'P&L'
            when trim(accttype) in ('Cost of Goods Sold')                              then 'P&L'
            when trim(accttype) in ('Expense', 'Other Expense')                        then 'P&L'
            when trim(accttype) in ('Bank', 'Accounts Receivable', 'Other Current Asset',
                                    'Fixed Asset', 'Other Asset', 'Deferred Expense')  then 'Balance Sheet'
            when trim(accttype) in ('Accounts Payable', 'Other Current Liability',
                                    'Long Term Liability', 'Deferred Revenue')         then 'Balance Sheet'
            when trim(accttype) in ('Equity', 'Retained Earnings')                     then 'Balance Sheet'
            else 'Unclassified'
        end                                                         as financial_statement,

        -- Derived: P&L sub-category
        case
            when trim(accttype) in ('Income', 'Other Income')      then 'Revenue'
            when trim(accttype) = 'Cost of Goods Sold'             then 'COGS'
            when trim(accttype) in ('Expense', 'Other Expense')    then 'Operating Expense'
            else null
        end                                                         as pl_category,

        -- Derived: Balance Sheet sub-category
        case
            when trim(accttype) in ('Bank', 'Accounts Receivable',
                                    'Other Current Asset')         then 'Current Asset'
            when trim(accttype) in ('Fixed Asset', 'Other Asset',
                                    'Deferred Expense')            then 'Non-Current Asset'
            when trim(accttype) in ('Accounts Payable',
                                    'Other Current Liability',
                                    'Deferred Revenue')            then 'Current Liability'
            when trim(accttype) = 'Long Term Liability'            then 'Non-Current Liability'
            when trim(accttype) in ('Equity', 'Retained Earnings') then 'Equity'
            else null
        end                                                         as bs_category,

        _fivetran_synced                                            as fivetran_synced_at,

        -- dedup: keep latest fivetran sync per account id
        row_number() over (
            partition by id
            order by _fivetran_synced desc
        )                                                           as _row_num

    from source
    where isinactive = false
)

select * exclude (_row_num)
from cleaned
where _row_num = 1
