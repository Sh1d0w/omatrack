# Reports & export

`views/ReportsView.qml` — the dashboard's **Reports** tab. One report per
(range, group-by); the helper computes the rows server-side, QML only
renders them, so heavy intervals stay fast.

## Controls

- **Range** — the shared `DateRangeBar` (same six presets + manual fields as
  Entries; see [entries.md](entries.md)). Date-only, local calendar,
  inclusive; the filter matches an entry's **start**.
- **Group by** — three selected-buttons: **Day** (default), **Client**,
  **Project**. Switching group-by resets to page 1.
- **Export CSV** / **Export HTML** — pinned to the far right of the
  group-by row (anchored to the shared bottom edge, not a stretch spacer);
  write the current range's raw entries to `~/Downloads` (see below); a
  flash reports `Exported N entries to <path>`.

Note: the report deliberately shows **all** entries in the range (no
client/project/billable/search filter is offered — `billable: null`,
`search: ""`), because its purpose is the overall breakdown; per-client
breakdown is the *Client* group-by.

## Output

A list of rows, each:

| Group-by | Label | Ordering |
|----------|-------|----------|
| day      | local date `YYYY-MM-DD` | chronological |
| client   | client name | seconds, descending |
| project  | `Client — Project` | seconds, descending |

with `HH:MM` total and a muted `billable HH:MM` per row.

Rows are paginated **server-side** at the fixed page size (15 —
`service.pageSize`). A shared `PaginationBar`
(`components/PaginationBar.qml`) is pinned to the bottom of the list with
the flash/error status texts to its right.

Row shape from the helper: `{ key, label, seconds, billableSeconds }` +
response `total`, `totalSeconds`, `billableSeconds`, `offset`, `limit`.

## Export files

`export --format csv|html` takes the same range/filter object as `report`
(the UI passes the range with no other filters), writes to
`~/Downloads/timesheet_<from|all>_<to|all>.<ext>` and returns
`{ ok, path, count, seconds }`. Files are plain documents (this runtime has
no QtWebEngine), opened by the user from the file manager/CLI:

### CSV

Exact header:

```
Start,End,Client,Project,Description,Billable,Duration (hours),Price
```

- one row per matching entry, sorted by start **ascending**;
- times as local `YYYY-MM-DD HH:MM`;
- `Billable` as `1`/`0`;
- `Duration (hours)` with 2 decimals;
- `Price` = entry hours × `hourlyRate` (settings), rounded to 2 decimals,
  prefixed with the configured `currency` (e.g. `EUR 123.45`; bare number
  when the currency is empty);
- a final total row: `total (N entries)` followed by the total hours and
  the total price (sum of the rounded row prices);
- proper CSV quoting via the stdlib `csv` module.

### HTML

A self-contained monospace timesheet page: title, a meta line (range
summary + generated timestamp), a table with the same columns as the CSV
(times shown as `YYYY-MM-DD HH:MM`, billable as `1`/`0`, prices with the
settings currency), and a `tfoot` total row (entry count, total hours,
total price). The numeric columns (Billable, Duration, Price) are
centered in both the header cells and the data cells, so headers and
values align. No external assets.

## CLI

```sh
python3 timetrack.py report --from 2026-08-01 --to 2026-08-31 --group-by client
python3 timetrack.py export --format csv --from 2026-08-01 --out /tmp/timesheet.csv
# --out is always required for the CLI; the UI passes its own path
# (~/Downloads/…).
```

`report`/`export` take only a shared lock — they never mutate state.
