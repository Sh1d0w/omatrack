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
- **Responsive mode** — while the window is wide enough, the presets
  sit left and the group-by right on one row. Below the width where
  those two button rows would overlap, both are swapped for labeled
  `Dropdown` controls in the same left/right placement: the six
  presets become a **Range** dropdown and the three options a
  **Group by** dropdown, so the filters never overlap at narrow
  window sizes. The range dropdown drives the same
  `DateRangeBar.applyPreset()` path as the buttons, so the
  preset→dates conversion has a single implementation.
- **Client** — labeled dropdown on the action row (left of the export
  buttons), so it is unaffected by the responsive swap above. Default
  **All clients**; a concrete client narrows both the report rows and
  the export to that client's entries. Changing it resets to page 1.
  It is the only non-range filter the report offers (see the note
  below).
- **Export CSV** / **Export HTML** — pinned to the far right of the
  action row; export **exactly what the report is showing** — the
  preset's `from`/`to` plus the active client filter are passed
  straight to the helper with no other filters, so the file always
  matches what the table is showing; write to `~/Downloads` (see
  below); a flash reports `Exported N entries to <path>`.

Note: the report deliberately shows **all** entries in the range except
the client filter (no project/billable/search filter is offered —
`projectId: ""`, `billable: null`, `search: ""`), because its purpose is
the overall breakdown; per-client breakdown is the *Client* group-by.
The client filter narrows that breakdown to one client — useful for a
per-client timesheet; with the *Client* group-by it yields exactly one
row.

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
Start,End,Client,Project,Description,Billable,Duration,Price
```

- one row per matching entry, sorted by start **ascending**;
- times as local `YYYY-MM-DD HH:MM`;
- `Billable` as `1`/`0`;
- `Duration` in the same human-readable shape the report rows use —
  `1h 32m` / `45m` / `0m` (the helper's `_duration_str`, mirroring the
  service's `fmtDur`); decimal hours (e.g. `0.89`) read as an opaque
  number, so they are not shown;
- `Price` = entry seconds × `hourlyRate` / 3600 (settings), rounded to
  2 decimals, prefixed with the configured `currency` (e.g. `EUR
  123.45`; bare number when the currency is empty) — money is computed
  from the exact seconds, not from the displayed duration;
- a final total row: `total (N entries)` followed by the total
  duration (same `1h 32m` shape) and the total price (sum of the
  rounded row prices);
- proper CSV quoting via the stdlib `csv` module.

### HTML

A self-contained monospace timesheet page: title, a meta line (filter
summary — the range and, when filtered, the client's **name** — plus a
generated timestamp), a table with the same columns as the CSV (times
shown as `YYYY-MM-DD HH:MM`, billable as `1`/`0`, durations in the
`1h 32m` shape, prices with the settings currency), and a `tfoot` total
row (entry count, total duration, total price). The numeric columns
(Billable, Duration, Price) are centered in both the header cells and
the data cells, so headers and values align. No external assets.

## CLI

```sh
python3 omatrack.py report --from 2026-08-01 --to 2026-08-31 --group-by client
python3 omatrack.py report --group-by day --client-id <client-id>
python3 omatrack.py export --format csv --from 2026-08-01 --out /tmp/timesheet.csv
python3 omatrack.py export --format html --client-id <client-id> --out /tmp/timesheet.html
# --out is always required for the CLI; the UI passes its own path
# (~/Downloads/…).
```

`report`/`export` take only a shared lock — they never mutate state.
