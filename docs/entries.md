# Entries

`views/EntriesView.qml` — the dashboard's **Entries** tab: filterable,
paginated list of all time entries, with manual add, edit, and delete —
all through the filter row and centered card overlays.

## Filtering

Two control rows above the list:

**Date presets** — `DateRangeBar` (`components/DateRangeBar.qml`, shared
with Reports): buttons `Today`, `Yesterday`, `7 days`, `This month`,
`Last month`, `All`, plus manual `YYYY-MM-DD → YYYY-MM-DD` fields. Presets
are computed on the **local calendar**; typing into a field switches the
preset to manual (`preset ""`). Date-only ranges match entries whose
**start** is in the inclusive local-day range (the helper resolves
`from`/`to` to local `00:00:00` / `23:59:59`).

**Field filters + add** — the filter row holds the dropdowns, the search
field, and the **`Add manual entry`** button pinned to the row's far
right, bottom-aligned with the dropdown fields (anchored to the row's
right/bottom edges, not a stretch spacer, so it holds its position at any
window width). Each filter change re-queries immediately (search is
debounced 300 ms):

| Filter     | Options                                        |
|------------|------------------------------------------------|
| Client     | All clients + every client                     |
| Project    | All projects + every project (all clients)     |
| Billable   | All / Billable / Non-billable                  |
| Search     | case-insensitive substring over description, client name, project name |

Any filter change resets to page 1 (`applyFilters` → `queryAt(0)`).

## The list

- Paginated server-side at the global **page size** (the `pageSize`
  setting, default 50 — see [settings.md](settings.md)); the full entries
  array never enters QML (see [architecture.md](architecture.md)). After a
  delete that empties the page, the current page is re-fetched.
- Each row is an `EntryRow` (`components/EntryRow.qml`): local
  `d MMM HH:mm` + `Client — Project` (bold), description (or `-`), a red
  `billable` mark when set, duration `HH:MM:SS` (bold). Clicking the row
  (or **Edit**) opens the edit card; **Del** asks for confirmation.
- Initial load fires once the service is injected (0 ms one-shot `Timer`).

## Pager + status

Pinned to the bottom of the table, above the totals bar: the shared
`PaginationBar` (`components/PaginationBar.qml`) with `←` / `→` around
`Showing X–Y of Z`, plus the global page-size selector
(`10/25/50/100 / page`, writes `settings.pageSize`), and to its right the
flash text (accent, 2 s) and the service's `lastError` (red). Changing the
page size keeps the same entry at the top of the page (the offset is
re-mapped to the same page index, clamped to the last page).

## Totals bar

`Total HH:MM · billable HH:MM · N entries` — computed by the helper over
the **whole filtered set**, not just the page.

## Add entry

`Add manual entry` (filter row, far right) opens a centered modal on a
scrim — `CardOverlay` (`components/CardOverlay.qml`, shared with the edit
card below): title, `EntryForm` (date, time, minutes, then the shared
`TaskForm`), `Add entry` and `Close`.

- `EntryForm` pre-fills once, when the service is injected
  (`defaultsToToday()`: today, current local time, 60 minutes, last-used
  client/project via `applyDefaults()`). A half-filled form survives
  close/reopen.
- `Add entry` is gated on `entryForm.valid` (well-formed date/time,
  minutes ≥ 1, client + project set); an invalid submit sets
  `lastError = "Fill in a valid manual entry"`.
- A successful add closes the modal, flashes `Entry added`, and
  re-queries the current page.
- **Scrim click or Esc dismisses** — the same semantics as the edit card
  and the window-level confirm dialog. Esc routes through the view's
  `handleKey` (the dashboard's key gate forwards it); while a card is open
  the view reports `inputActive`, so the window key catcher does not
  swallow the keys or close the window.

## Edit card (overlay)

`CardOverlay` (shared with the manual-entry modal above) while
`editEntry !== null`: a centered 420px `BorderSurface` card (accent border,
`Style.cornerRadius`) on a `Util.alpha(Color.background, 0.7)` scrim
(`z: 10`) — the same visual language and dismissal semantics as the
window-level confirm dialog: **scrim click or Esc discards** (Esc via the
view's `handleKey`, routed by the dashboard's key gate). Contains an
`EntryForm`:

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

`Del` (row or card) → the window-level confirm dialog (see
[dashboard.md](dashboard.md)) with "Delete this time entry?" →
`service.deleteEntry(id)`. On success the edit overlay (if open) closes,
`Entry deleted` flashes, and the current page re-fetches. Delete is
unconditional at the data layer (no referential children on an entry).
Failures surface in the red error line.

## Data semantics (helper side)

- `entry-add --start YYYY-MM-DD --time HH:MM[:SS] --minutes N --client-id …
  --project-id … [--description …] [--billable 0|1]`: start is local time
  converted to UTC; `end = start + minutes`; `minutes ≥ 1`.
- `entry-update` recombines date/time/minutes when any are given (missing
  pieces keep the current value); client/project are optional and validated
  (project must belong to the client); errors if nothing changed.
- The start range-filter and report matching always use the entry's **start**;
  an entry is never split across days.
