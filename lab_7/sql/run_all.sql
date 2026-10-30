\set ON_ERROR_STOP on
\pset pager off
\timing on

\ir 01_schema.sql
\ir 02_seed.sql
\ir 03_views.sql
\ir 04_functions_triggers.sql
\ir 05_optimization.sql
\ir 06_queries.sql

\timing off
