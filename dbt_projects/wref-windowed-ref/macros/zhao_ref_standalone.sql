{#
  zhao_utils -- wref() / zhao_window_start() / zhao_window_end()
  Standalone copy-paste variant, from https://github.com/allenhori/zhao_dbt_utils
  (standalone/zhao_ref_standalone.sql, v0.2.0). See that repo's README for the
  full design rationale. Bare calls -- {{ wref(...) }}, no namespace prefix --
  since this file lives directly in this project's own macros/ folder.
#}

{% macro _zhao_find_node(model_name) %}
  {%- set found = namespace(node=none) -%}
  {%- for node in graph.nodes.values() -%}
    {%- if node.name == model_name and found.node is none -%}
      {%- set found.node = node -%}
    {%- endif -%}
  {%- endfor -%}
  {%- if found.node is none -%}
    {{ exceptions.raise_compiler_error(
      "zhao_utils: no model named '" ~ model_name ~ "' found in the graph"
    ) }}
  {%- endif -%}
  {{ return(found.node) }}
{% endmacro %}

{% macro _zhao_current_meta() %}
  {%- if not execute -%}
    {{ return(none) }}
  {%- endif -%}
  {{ return((model.config.get('meta', {}) or {}).get('zhao')) }}
{% endmacro %}

{%- macro _zhao_arg_name(direction) -%}
  {{ return('expand_back' if direction == 'lookback' else 'expand_forward') }}
{%- endmacro -%}

{% macro _zhao_resolve(upstream_name, direction, explicit_value, explicit_unit) %}
  {%- set meta = _zhao_current_meta() -%}
  {%- set arg_name = _zhao_arg_name(direction) -%}
  {%- set unit_arg_name = arg_name ~ '_unit' -%}

  {%- if explicit_value is none and explicit_unit is not none and execute -%}
    {{ exceptions.raise_compiler_error(
      "zhao_utils: " ~ unit_arg_name ~ "='" ~ explicit_unit ~ "' was passed for a read of '"
      ~ upstream_name ~ "' without " ~ arg_name ~ " -- a unit with no amount doesn't mean "
      ~ "anything. Pass " ~ arg_name ~ " too, or drop " ~ unit_arg_name ~ " and let it come "
      ~ "from meta.zhao."
    ) }}
  {%- endif -%}

  {%- if explicit_value is not none and execute -%}
    {%- if meta is none -%}
      {%- do exceptions.warn(
        "zhao_utils: " ~ arg_name ~ "=" ~ explicit_value ~ " was passed for a read of '"
        ~ upstream_name ~ "', but the current model has no meta.zhao block. This compiles and runs "
        ~ "fine using the value you gave -- but zhao-dbt-plan's planner won't see it, so its plan "
        ~ "for this model will be inaccurate. Add a meta.zhao config to unlock accurate planning."
      ) -%}
      {{ return({'amount': explicit_value, 'unit': explicit_unit if explicit_unit is not none else 'day'}) }}
    {%- endif -%}
    {%- set overrides = meta.get(direction ~ '_overrides', {}) or {} -%}
    {%- set configured_value = overrides.get(upstream_name, meta.get(direction)) -%}
    {%- if configured_value != explicit_value -%}
      {{ exceptions.raise_compiler_error(
        "zhao_utils: " ~ arg_name ~ "=" ~ explicit_value ~ " passed at the call site for a "
        ~ "read of '" ~ upstream_name ~ "' does not match the effective meta.zhao." ~ direction
        ~ " value (" ~ configured_value ~ "). Keep these in sync, or drop the argument to trust "
        ~ "meta.zhao."
      ) }}
    {%- endif -%}
    {%- set configured_unit = meta.get(direction ~ '_unit', 'day') -%}
    {%- if explicit_unit is not none and explicit_unit != configured_unit -%}
      {{ exceptions.raise_compiler_error(
        "zhao_utils: " ~ unit_arg_name ~ "='" ~ explicit_unit ~ "' passed at the call site for a "
        ~ "read of '" ~ upstream_name ~ "' does not match the effective meta.zhao." ~ direction
        ~ "_unit value ('" ~ configured_unit ~ "'). Keep these in sync, or drop the argument to "
        ~ "trust meta.zhao."
      ) }}
    {%- endif -%}
    {{ return({'amount': explicit_value, 'unit': configured_unit}) }}
  {%- endif -%}

  {%- if meta is none -%}
    {{ return(none) }}
  {%- endif -%}
  {%- set overrides = meta.get(direction ~ '_overrides', {}) or {} -%}
  {%- set amount = overrides.get(upstream_name, meta.get(direction, 0)) -%}
  {{ return({'amount': amount, 'unit': meta.get(direction ~ '_unit', 'day')}) }}
{% endmacro %}

{%- macro _zhao_days(resolved) -%}
  {%- set unit = resolved['unit'] -%}
  {%- if unit not in ('day', 'week') -%}
    {{ exceptions.raise_compiler_error(
      "zhao_utils: lookback_unit/lookahead_unit '" ~ unit
      ~ "' isn't supported yet (v1 only supports day/week) -- see this package's README."
    ) }}
  {%- endif -%}
  {{ return(resolved['amount'] * (7 if unit == 'week' else 1)) }}
{%- endmacro -%}

{% macro zhao_window_start(upstream_name, expand_back=none, expand_back_unit=none) %}
  {%- if not execute -%}
    {{ return('') }}
  {%- endif -%}
  {%- set resolved = _zhao_resolve(upstream_name, 'lookback', expand_back, expand_back_unit) -%}
  {%- set literal_start = "cast('" ~ model.batch.event_time_start ~ "' as " ~ dbt.type_timestamp() ~ ")" -%}
  {%- if resolved is none -%}
    {{ return(literal_start) }}
  {%- endif -%}
  {%- set days = _zhao_days(resolved) -%}
  {{ return(dbt.dateadd('day', -1 * days, literal_start)) }}
{% endmacro %}

{% macro zhao_window_end(upstream_name, expand_forward=none, expand_forward_unit=none) %}
  {%- if not execute -%}
    {{ return('') }}
  {%- endif -%}
  {%- set resolved = _zhao_resolve(upstream_name, 'lookahead', expand_forward, expand_forward_unit) -%}
  {%- set literal_end = "cast('" ~ model.batch.event_time_end ~ "' as " ~ dbt.type_timestamp() ~ ")" -%}
  {%- if resolved is none -%}
    {{ return(literal_end) }}
  {%- endif -%}
  {%- set days = _zhao_days(resolved) -%}
  {{ return(dbt.dateadd('day', days, literal_end)) }}
{% endmacro %}

{% macro wref(upstream_name, expand_back=none, expand_forward=none, expand_back_unit=none, expand_forward_unit=none) %}
  {%- if not execute -%}
    {{ return(ref(upstream_name)) }}
  {%- endif -%}
  {%- set meta = _zhao_current_meta() -%}
  {%- if meta is none and expand_back is none and expand_forward is none
        and expand_back_unit is none and expand_forward_unit is none -%}
    {{ return(ref(upstream_name)) }}
  {%- endif -%}
  {%- set upstream_node = _zhao_find_node(upstream_name) -%}
  {%- set event_time_col = upstream_node.config.get('event_time') -%}
  {%- if event_time_col is none -%}
    {{ exceptions.raise_compiler_error(
      "zhao_utils: the current model has a meta.zhao block covering a read of '"
      ~ upstream_name ~ "', but '" ~ upstream_name ~ "' has no event_time configured -- wref() "
      ~ "needs event_time on the upstream to know which column to filter on."
    ) }}
  {%- endif -%}
  {%- set start = zhao_window_start(upstream_name, expand_back, expand_back_unit) -%}
  {%- set end = zhao_window_end(upstream_name, expand_forward, expand_forward_unit) -%}
(
  select * from {{ ref(upstream_name).render() }}
  where {{ event_time_col }} >= {{ start }}
    and {{ event_time_col }} < {{ end }}
)
{% endmacro %}
