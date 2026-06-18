-- ============================================================
-- The output have been generated with the assistance of Claude at 2026-06-18T09:52:56Z UTC.
-- The content has been verified by the designated engineer.
-- ============================================================
{#
  Macro   : generate_schema_name
  Purpose : Override dbt default schema-naming to use custom_schema_name directly
            (UPPER-cased), without prepending the target schema.
            Ensures SILVER models land in SILVER, GOLD in GOLD, etc.
  Usage   : Automatically called by dbt — do not invoke directly.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
