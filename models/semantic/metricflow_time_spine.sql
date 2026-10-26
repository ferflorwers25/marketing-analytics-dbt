-- Daily calendar used by the semantic layer (MetricFlow) to compute metrics over time.
{{ dbt_utils.date_spine(datepart="day", start_date="cast('2025-01-01' as date)", end_date="cast('2027-12-31' as date)") }}
