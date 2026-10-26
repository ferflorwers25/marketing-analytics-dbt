{#- Generic test: fails for every row where the column is below zero. -#}
{% test not_negative(model, column_name) %}
select {{ column_name }}
from {{ model }}
where {{ column_name }} < 0
{% endtest %}
