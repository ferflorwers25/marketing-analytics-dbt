{#-
  Returns the value of a query-string parameter from a URL, or null.
  Regex functions differ between warehouses, so the macro dispatches per adapter.
-#}
{% macro extract_url_param(url, param) -%}
    {{ return(adapter.dispatch('extract_url_param', 'marketing_analytics')(url, param)) }}
{%- endmacro %}

{% macro default__extract_url_param(url, param) -%}
    nullif(regexp_substr({{ url }}, '[?&]{{ param }}=([^&#]*)', 1, 1, 'e', 1), '')
{%- endmacro %}

{% macro duckdb__extract_url_param(url, param) -%}
    nullif(regexp_extract({{ url }}, '[?&]{{ param }}=([^&#]*)', 1), '')
{%- endmacro %}
