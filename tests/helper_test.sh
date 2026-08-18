#!/usr/bin/env bash
# End-to-end tests for timetrack.py against a throwaway state dir.
# Usage: bash tests/helper_test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export XDG_STATE_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_STATE_HOME"' EXIT

PY=(python3 "$ROOT/timetrack.py")
CSV_FILE="$XDG_STATE_HOME/exports/timesheet.csv"
HTML_FILE="$XDG_STATE_HOME/exports/timesheet.html"

pass=0
fail=0

check() { # check <label> <extended-regex> <line>
  local label="$1" pattern="$2" line="$3"
  if printf '%s' "$line" | grep -qE "$pattern"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label"
    echo "      expected match: $pattern"
    echo "      line: $line"
  fi
}

ok()  { check "$1" '"ok": true'  "$2"; }
err() { check "$1" '"ok": false' "$2"; }

must() { # must <label> <shell-expression>
  local label="$1" expr="$2"
  if eval "$expr"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label"
  fi
}

jget() { # jget <json-line> <python-expr evaluated with name d>
  printf '%s' "$1" | python3 -c \
    'import json, sys; d = json.load(sys.stdin); print(eval(sys.argv[1], {"d": d}))' "$2"
}

# --- setup + CRUD guards ----------------------------------------------------

L="$("${PY[@]}" init 2>&1 || true)"
ok "init" "$L"

L="$("${PY[@]}" client-add --name Acme 2>&1 || true)"
ok "client-add Acme" "$L"
CID="$(jget "$L" 'd["state"]["clients"][-1]["id"]')"

L="$("${PY[@]}" client-add --name "  acme  " 2>&1 || true)"
err "duplicate client (case/whitespace) rejected" "$L"
check "duplicate client error message" '"client already exists"' "$L"

L="$("${PY[@]}" project-add --client-id "$CID" --name Website 2>&1 || true)"
ok "project-add Website" "$L"
PID="$(jget "$L" 'd["state"]["projects"][-1]["id"]')"

L="$("${PY[@]}" project-add --client-id c_missing --name Ghost 2>&1 || true)"
err "project for missing client rejected" "$L"
check "missing client error" '"client not found: c_missing"' "$L"

# --- timer lifecycle ----------------------------------------------------------

L="$("${PY[@]}" start --client-id "$CID" --project-id "$PID" --description "Landing hero" --billable 1 2>&1 || true)"
ok "start" "$L"
check "start sets active" '"active": {' "$L"

L="$("${PY[@]}" start --client-id "$CID" --project-id "$PID" --description x --billable 1 2>&1 || true)"
err "second start rejected" "$L"
check "second start error message" '"timer already running"' "$L"

# Timestamps are second-resolution: give the active entry a full second
# so a fast machine cannot produce a 0-second duration.
sleep 1.1
L="$("${PY[@]}" stop 2>&1 || true)"
ok "stop" "$L"
check "stop clears active" '"active": null' "$L"

L="$("${PY[@]}" entries 2>&1 || true)"
ok "entries (no filter)" "$L"
check "entries total is 1" '"total": 1,' "$L"
check "entries totalSeconds > 0" '"totalSeconds": [1-9][0-9]*' "$L"
EID1="$(jget "$L" 'd["entries"][0]["id"]')"

L="$("${PY[@]}" entries --search "HERO" 2>&1 || true)"
ok "entries search" "$L"
check "search matches description (case-insensitive)" '"total": 1,' "$L"

L="$("${PY[@]}" entries --search "zzz-nope" 2>&1 || true)"
check "search without match is empty" '"total": 0,' "$L"

L="$("${PY[@]}" report --group-by client 2>&1 || true)"
ok "report by client" "$L"
check "report row label is client name" '"label": "Acme"' "$L"

# --- manual entry add / update / delete ---------------------------------------

L="$("${PY[@]}" entry-add --start 2026-08-01 --time 09:00 --minutes 120 --client-id "$CID" --project-id "$PID" --description "Manual task" --billable 0 2>&1 || true)"
ok "entry-add" "$L"

L="$("${PY[@]}" entries --search "Manual task" 2>&1 || true)"
EID2="$(jget "$L" 'd["entries"][0]["id"]')"
check "entry-add stores minutes as seconds" '"seconds": 7200' "$L"

L="$("${PY[@]}" entry-update --id "$EID2" --minutes 90 2>&1 || true)"
ok "entry-update minutes" "$L"

L="$("${PY[@]}" entries --search "Manual task" 2>&1 || true)"
check "entry-update recomputes seconds" '"seconds": 5400' "$L"

L="$("${PY[@]}" entry-delete --id "$EID2" 2>&1 || true)"
ok "entry-delete" "$L"

L="$("${PY[@]}" entries --search "Manual task" 2>&1 || true)"
check "deleted entry is gone" '"total": 0,' "$L"

# --- delete guards -------------------------------------------------------------

L="$("${PY[@]}" client-delete --id "$CID" 2>&1 || true)"
err "client-delete blocked while referenced" "$L"
check "client-delete error shape" '"client-delete blocked: [0-9]+ projects, [0-9]+ entries' "$L"

L="$("${PY[@]}" project-delete --id "$PID" 2>&1 || true)"
err "project-delete blocked while entry references it" "$L"
check "project-delete error shape" '"project-delete blocked: [0-9]+ entries' "$L"

# --- settings persistence --------------------------------------------------------

L="$("${PY[@]}" settings-set --json '{"currency": "USD", "hourlyRate": 90, "invoice": {"companyName": "Me UG", "taxRate": 19}}' 2>&1 || true)"
ok "settings-set" "$L"

L="$("${PY[@]}" state 2>&1 || true)"
ok "state re-read" "$L"
check "settings persisted: currency" '"currency": "USD"' "$L"
check "settings persisted: hourlyRate" '"hourlyRate": 90' "$L"
check "settings persisted: companyName" '"companyName": "Me UG"' "$L"

# --- exports ----------------------------------------------------------------------

L="$("${PY[@]}" export --format csv --out "$CSV_FILE" 2>&1 || true)"
ok "export csv" "$L"
must "csv file exists" '[ -f "$CSV_FILE" ]'
must "csv header exact" '[ "$(sed -n 1p "$CSV_FILE")" = "start,end,client,project,description,billable,duration_seconds,duration_hours" ]'
must "csv has one data row" '[ "$(wc -l < "$CSV_FILE")" -eq 2 ]'

L="$("${PY[@]}" export --format html --out "$HTML_FILE" 2>&1 || true)"
ok "export html" "$L"
must "html file exists" '[ -f "$HTML_FILE" ]'
must "html totals row" 'grep -q "total (1 entries)" "$HTML_FILE"'

# --- invoices -----------------------------------------------------------------------

L="$("${PY[@]}" invoice --client-id "$CID" --from 2020-01-01 --to 2030-12-31 2>&1 || true)"
ok "invoice #1" "$L"
INV1="$(jget "$L" 'd["path"]')"
check "invoice #1 number" '"number": "INV-0001"' "$L"
must "invoice #1 file exists" '[ -f "$INV1" ]'
must "invoice #1 shows company name" 'grep -q "Me UG" "$INV1"'
must "invoice #1 shows client" 'grep -q "Acme" "$INV1"'
must "invoice #1 shows number" 'grep -q "INV-0001" "$INV1"'
must "invoice #1 shows tax line" 'grep -q "Tax 19%" "$INV1"'

# --- teardown: guards lift once references are gone ---------------------------------

L="$("${PY[@]}" entry-delete --id "$EID1" 2>&1 || true)"
ok "entry-delete (last entry)" "$L"

L="$("${PY[@]}" project-delete --id "$PID" 2>&1 || true)"
ok "project-delete allowed after entry delete" "$L"

L="$("${PY[@]}" client-delete --id "$CID" 2>&1 || true)"
ok "client-delete allowed when unreferenced" "$L"

# --- invoice number sequence advances ---------------------------------------------

L="$("${PY[@]}" client-add --name Beta 2>&1 || true)"
ok "client-add Beta" "$L"
CID2="$(jget "$L" 'd["state"]["clients"][-1]["id"]')"

L="$("${PY[@]}" project-add --client-id "$CID2" --name API 2>&1 || true)"
ok "project-add API" "$L"
PID2="$(jget "$L" 'd["state"]["projects"][-1]["id"]')"

L="$("${PY[@]}" entry-add --start 2026-08-10 --time 10:00 --minutes 60 --client-id "$CID2" --project-id "$PID2" --description "API work" --billable 1 2>&1 || true)"
ok "entry-add billable for invoice #2" "$L"

L="$("${PY[@]}" invoice --client-id "$CID2" --from 2020-01-01 --to 2030-12-31 2>&1 || true)"
ok "invoice #2" "$L"
check "invoice #2 number increments" '"number": "INV-0002"' "$L"

echo
echo "passed: $pass  failed: $fail"
if [ "$fail" -ne 0 ]; then
  echo "FAIL"
  exit 1
fi
echo "PASS"
