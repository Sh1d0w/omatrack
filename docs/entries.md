# Entries

`views/EntriesView.qml` — the dashboard's **Entries** tab: filterable,
paginated list of all time entries with manual add/edit/delete.

## Filtering

Two control rows above the list:

**Date presets** — `DateRangeBar` (`components/DateRangeBar.qml`, shared
with Reports): buttons `Today`, `Yesterday`, `7 days`, `This month`,
`Last month`, `All`, plus manual `YYYY-MM-DD → YYYY-MM-DD` fields. Presets
are computed on the **local calendar**; typing into a field switches the
preset to manual (`preset ""`). Date-only ranges match entries whose
**start** is in the inclusive local-day range (the helper resolves
`from`/`to` to local `00:00:00` / `23:59:59`).

**Field filters** — each change re-queries immediately (search is debounced
300 ms):

| Filter     | Options                                        |
|------------|------------------------------------------------|
| Client     | All clients + every client                     |
| Project    | All projects + every project (all clients)     |
| Billable   | All / Billable / Non-billable                  |
| Search     | case-insensitive substring over description, client name, project name |

Any filter change resets to page 1 (`applyFilters` → `queryAt(0)`).

## The list

- Paginated: `limit 50` fixed; the full entries array never enters QML
  (see [architecture.md](architecture.md)). Pager row shows
  `Showing 1–50 of 132` with `←`/`→` buttons enabled by position; after a
  delete that empties the page, the current page is re-fetched.
- Each row is an `EntryRow` (`components/EntryRow.qml`): local
  `d MMM HH:mm` + `Client — Project` (bold), description (or `-`), a red
  `billable` mark when set, duration `HH:MM:SS` (bold). Clicking the row
  (or **Edit**) opens the edit card; **Del** asks for confirmation.
- Totals bar under the list: `Total HH:MM · billable HH:MM · N entries` —
  computed by the helper over the **whole filtered set**, not just the page.
- Initial load fires once the service is injected (0 ms one-shot `Timer`).

## Add entry

The header's **Add entry** button opens the edit card (same overlay) with an
empty `EntryForm` pre-filled by `defaultsToToday()`: today's date, current
local time, 60 minutes, and `taskForm.applyDefaults()` (last client +
project). Saving with no entry selected adds; with one selected, updates.

## Edit card (overlay)

Centered 420px card on a 40% dim (`z: 10`) while `editEntry !== null`.
Contains an `EntryForm`:

- **date** `YYYY-MM-DD`, **time** `HH:MM` (local), **minutes** 1–1440
  (`NumberField`), then the shared `TaskForm` (client, project, description,
  billable).
- `valid` requires all of: well-formed date + time, minutes ≥ 1, client and
  project set. Save with an invalid form sets `lastError = "Fill in a valid
  entry"`.
- Edit pre-fills from the entry: local date/time of `start`,
  `minutes = max(1, round(seconds/60))`, client, project, description,
  billable.
- **Save** → `service.updateEntry(id, patch, cb)`; success flashes
  `Entry saved` (2 s) and re-fetches the current page. **Delete** inside the
  card routes through the same confirm dialog. **Close** discards.

## Delete

`Del` (row or card) → `deleteId` + `ConfirmDialog`
("Delete this time entry?") → `service.deleteEntry(id)`. Delete is
unconditional at the data layer (no referential children on an entry).
Failures surface in the red error line.

## Data semantics (helper side)

- `entry-add --date YYYY-MM-DD --time HH:MM[:SS] --minutes N --client-id …
  --project-id … [--description …] [--billable 0|1]`: start is local time
  converted to UTC; `end = start + minutes`; `minutes ≥ 1`.
- `entry-update` recombines date/time/minutes when any are given (missing
  pieces keep the current value); client/project are optional and validated
  (project must belong to the client); errors if nothing changed.
- The start range-filter and report matching always use the entry's **start**;
  an entry is never split across days.
