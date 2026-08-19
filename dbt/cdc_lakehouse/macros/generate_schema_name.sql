{#
  dbt's default generate_schema_name macro concatenates the profile's target
  schema with a model's custom +schema config (e.g. "silver_gold"), which is
  not what we want here — models/gold should land in exactly `gold`, not
  `silver_gold`. Overriding to use the custom schema name verbatim when one
  is set. Known dbt gotcha, fixed here before it caused a confusing "table
  not found" the first time `dbt run` was actually tried.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
