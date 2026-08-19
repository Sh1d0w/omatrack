# Reports & export

`views/ReportsView.qml` — the dashboard's **Reports** tab. One report per
(range, group-by); the helper computes the rows server-side, QML only
renders them, so heavy intervals stay fast.

## Controls

- **Range** — the shared `DateRangeBar` in preset-only mode
  (`showPickers: false`): the six presets `Today`, `Yesterday`, `7 days`,
  `This month`, `Last month`, `All` (default **All**, no bounds). Manual
  From/To pickers live in the Entries filter and the invoice generate
  card, not here. Date-only, local calendar, inclusive; the filter
  matches an entry's **start**.
- **Group by** — three selected-buttons: **Day** (default), **Client**,
  **Project**; right-aligned on the same row as the presets. Switching
  group-by resets to page 1.
- **Export CSV** / **Export HTML** — pinned to the far right of their own
  row under the presets; export **exactly the currently filtered range**
  — the preset's `from`/`to` are passed straight to the helper with no
  other filters, so the file always matches what the report is showing;
  write to `~/Downloads` (see below); a flash reports `Exported N entries
  to <path>`.

Note: the report deliberately shows **all** entries in the range (no
client/project/billable/search filter is offered — `billable: null`,
`search: ""`), because its purpose is the overall breakdown; per-client
breakdown is the *Client* group-by.

## Output

The page opens with the shared heading ("Reports" title + muted
one-liner) like the other dashboard tabs, then the filter/export rows.

A list of rows (one per group, rendered by `components/ReportRow.qml`):

| Group-by | Label | Ordering |
|----------|-------|----------|
| day      | local date `YYYY-MM-DD` | chronological |
| client   | client name | seconds, descending |
| project  | `Client — Project` | seconds, descending |

Each row: the label (bold), a muted line `N entries · billable 1h 32m`
(plus ` · non-billable 1h 32m` when that part is > 0), a share hairline
(the row's share of the whole report's `totalSeconds`, so bars stay
comparable across pages — track + accent fill like the shell's OSD bar),
and the row's total on the right as `1h 32m` — the suffixed `fmtDur`
shape, since plain `H:MM` reads as minutes:seconds.

Rows are paginated **server-side** at the fixed page size (15 —
`service.pageSize`). A shared `PaginationBar`
(`components/PaginationBar.qml`) is pinned to the bottom of the list with
the flash/error status texts to its right.

Below the pager, a totals line: `Total 1h 32m · billable 1h 32m ·
N entries` — always the whole matched set, not just the current page.

Row shape from the helper: `{ key, label, seconds, billableSeconds,
count }` + response `total` (row count), `totalSeconds`,
`billableSeconds`, `entryCount` (matched entries), `offset`, `limit`.

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
python3 omatrack.py report --from 2026-08-01 --to 2026-08-31 --group-by client
python3 omatrack.py export --format csv --from 2026-08-01 --out /tmp/timesheet.csv
# --out is always required for the CLI; the UI passes its own path
# (~/Downloads/…).
```

`report`/`export` take only a shared lock — they never mutate state.
