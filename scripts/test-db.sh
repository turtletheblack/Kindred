#!/usr/bin/env bash
# Runs the migrations and checks against throwaway databases on a local
# Postgres, without Docker or a Supabase account. Each test file gets a
# fresh database.
#   PGHOST=/tmp PGPORT=5432 PGUSER=postgres scripts/test-db.sh
set -euo pipefail
cd "$(dirname "$0")/.."

db="kindred_test_$$"
trap 'psql -q -d postgres -c "drop database if exists $db" >/dev/null' EXIT

for test in supabase/tests/*_test.sql; do
  echo "== $test"
  psql -q -d postgres -c "drop database if exists $db" >/dev/null
  psql -v ON_ERROR_STOP=1 -q -d postgres -c "create database $db"
  psql -v ON_ERROR_STOP=1 -q -d "$db" -f supabase/tests/supabase_stub.sql
  for f in supabase/migrations/*.sql; do
    psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$f"
  done
  psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$test"
done
