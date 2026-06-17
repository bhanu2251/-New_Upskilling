-- Model: silver_account
-- Description: Cleaned Chart of Accounts from Bronze RAW.ACCOUNT
-- Grain: One row per account (unique ACCOUNT.ID)
-- Key fields: ACCTTYPE (determines financial statement), CASHFLOWRATE (cash flow category),
--             GENERALRATE (FX translation rate type), PARENT (account hierarchy)
-- No filters applied - reference table, all accounts included including inactive
--   (inactive flag handled downstream in Gold)

{{ config(
    materialized='table',
    schema='SILVER'
) }}

select
    id                                              as account_id,
    acctnumber                                      as account_number,
    accttype                                        as account_type,
    fullname                                        as account_full_name,
    displaynamewithhierarchy                        as account_display_name,
    parent                                          as parent_account_id,
    subsidiary                                      as subsidiary,
    cashflowrate                                    as cash_flow_rate,
    generalrate                                     as general_rate,
    issummary                                       as is_summary,
    isinactive                                      as is_inactive,
    eliminate                                       as eliminate,
    description                                     as account_description,

    -- Derived: financial statement classification
    case
        when accttype in ('Income', 'Other Income')                         then 'P&L'
        when accttype in ('Cost of Goods Sold')                             then 'P&L'
        when accttype in ('Expense', 'Other Expense')                       then 'P&L'
        when accttype in ('Bank', 'Accounts Receivable', 'Other Current Asset',
                          'Fixed Asset', 'Other Asset', 'Deferred Expense') then 'Balance Sheet'
        when accttype in ('Accounts Payable', 'Other Current Liability',
                          'Long Term Liability', 'Deferred Revenue')        then 'Balance Sheet'
        when accttype in ('Equity', 'Retained Earnings')                    then 'Balance Sheet'
        else 'Unclassified'
    end                                             as financial_statement,

    -- Derived: P&L sub-category
    case
        when accttype in ('Income', 'Other Income')      then 'Revenue'
        when accttype = 'Cost of Goods Sold'             then 'COGS'
        when accttype in ('Expense', 'Other Expense')    then 'Operating Expense'
        else null
    end                                             as pl_category,

    -- Derived: Balance Sheet sub-category
    case
        when accttype in ('Bank', 'Accounts Receivable',
                          'Other Current Asset')         then 'Current Asset'
        when accttype in ('Fixed Asset', 'Other Asset',
                          'Deferred Expense')            then 'Non-Current Asset'
        when accttype in ('Accounts Payable',
                          'Other Current Liability',
                          'Deferred Revenue')            then 'Current Liability'
        when accttype = 'Long Term Liability'            then 'Non-Current Liability'
        when accttype in ('Equity', 'Retained Earnings') then 'Equity'
        else null
    end                                             as bs_category,

    _fivetran_synced                                as fivetran_synced_at

from {{ source('raw', 'ACCOUNT') }}
