# Settings & CLI

`views/SettingsView.qml` — the dashboard's **Settings** tab — plus the full
`timetrack.py` command reference.

## The tab

`views/SettingsView.qml` organizes the settings into four sections —
**Billing** (currency, hourly rate), **Company** (company name, address),
**Tax & numbering** (tax rate, no. prefix, next number), and **Footer**
(footer text) — each introduced by a `PanelSectionHeader` under a
`PanelSeparator`. Every field is a shared `components/LabeledField.qml`
(body-size label above the kit TextField, muted helper line below),
laid out on an equal-width grid (2/2/3/1 columns, content capped at
720px) so all inputs in a row are the same size. The section stack
scrolls when the window is short; the save row, status texts, and the
data file path stay pinned at the bottom.

Local field copies sync from the service on load and whenever
`settings` changes (only while the tab is not dirty, so edits are never
clobbered). Any edit marks the tab dirty (`unsaved changes` chip);
**Save** validates locally, then pushes one patch via
`service.saveSettings(patch)` → `settings-set --json`; a successful save
shows a `Settings saved` flash for two seconds.

| Field        | Local validation | Notes |
|--------------|------------------|-------|
| Currency     | — (helper: non-empty, ≤ 8 chars, trimmed) | empty field saves `EUR` |
| Hourly rate  | finite, ≥ 0      | number |
| Company name | —                | printed in the invoice header |
| Address      | —                | printed under the company name |
| Tax rate %   | finite, 0–100    | helper accepts ≥ 0; the UI caps at 100 |
| No. prefix   | —                | default `INV-` |
| Next number  | integer ≥ 1      | helper: integer ≥ 0; the UI requires ≥ 1 so numbering never restarts at 0 |
| Footer       | —                | optional line at the bottom of every invoice |

Helper-side `settings-set --json '{...}'` accepts a **partial patch** over
the top-level keys and/or the `invoice` object; unknown fields error.
The data file path is printed at the bottom of the tab
(`service.statePath`).

## CLI reference

`python3 timetrack.py <command> [options]` — one JSON line on stdout,
`{"ok": true, ...}` (exit 0) or `{"ok": false, "error": "..."}` (exit 1).
Every command takes the flock (shared for reads, exclusive for writes);
mutation commands return the compact view (state minus entries +
`lastUsed`, day totals, `entryCount`).

| Command | Arguments | Notes |
|---------|-----------|-------|
| `init` | `[--print-dir]` | create state file + directories (idempotent); `--print-dir` prints the state dir |
| `state` | — | ensure state; print the current state view |
| `start` | `--client-id --project-id --description [--billable 0\|1]` | `--description` is **mandatory** (blank/whitespace → `description is required`); error if a timer is already running; persists `active` immediately (billable defaults 1) |
| `stop` | `[--at ISO-8601]` | closes `active` into `entries`; the stored duration **excludes paused segments** (stopping while paused closes at the pause moment); naive `--at` is UTC |
| `pause` | — | freezes `active`: `paused: true`, `pauseStart` = now; rejects `no timer running` / `timer is already paused` |
| `resume` | — | banks the pause segment into `pausedSeconds` and clears the flags; rejects `no timer running` / `timer is not paused` |
| `entries` | `[--from --to] [--client-id] [--project-id] [--billable 0\|1] [--search] [--offset N] [--limit N]` | start-DESC list; limit clamped 1..500 (default 50); plus `total`, `totalSeconds`, `billableSeconds`, `nextOffset` (null on last page) |
| `report` | `--group-by day\|client\|project [--from --to] [--client-id] [--project-id] [--offset N] [--limit N]` | aggregated rows, paginated (limit clamped 1..500, default 50); billable/search are **not accepted** (all matched entries count); `totalSeconds`/`billableSeconds` cover the **whole** matched set, not just the page |
| `client-add` | `--name` | case-insensitive duplicate rejected |
| `client-update` | `--id --name` | same duplicate check |
| `client-delete` | `--id` | blocked while referenced by projects/entries |
| `project-add` | `--client-id --name` | unique per client |
| `project-update` | `--id [--name] [--client-id]` | `--client-id` moves the project |
| `project-delete` | `--id` | blocked while referenced by entries |
| `entry-add` | `--start YYYY-MM-DD --time HH:MM[:SS] --minutes N --client-id --project-id [--description] [--billable 0\|1]` | local date/time → UTC start; `end = start + minutes` |
| `entry-update` | `--id [--start YYYY-MM-DD] [--time] [--minutes] [--client-id] [--project-id] [--description] [--billable 0\|1]` | missing date/time fall back to the entry's current values; errors if nothing changed |
| `entry-delete` | `--id` | unconditional |
| `settings-set` | `--json '{...}'` | partial patch (see table above) |
| `export` | `--format csv\|html --out PATH [--from --to] [--client-id] [--project-id] [--billable 0\|1]` | read-only; CSV/HTML timesheet (see reports-export.md) |
| `invoice` | `--client-id --from --to [--out PATH]` | billable entries, per project, at the configured rate (see invoices.md) |

## IPC (bar-side control)

The service declares the plugin's single `IpcHandler { target: "timetrack" }`
(the popup runs `manageIpc: false` so it never collides):

| Call | Returns |
|------|---------|
| `ping` | `"ok"` |
| `status` | `{ running, paused, client, project, description, billable, elapsedSeconds, daySeconds, dayBillableSeconds, entryCount, lastResult }` — `elapsedSeconds` excludes paused time; `lastResult` is the previous start/stop/pause/resume's response (optimistic IPC: those calls return before the helper finishes; the outcome lands in the next `status`) |
| `start` / `stop` / `pause` / `resume` / `toggle` | optimistic; `start` takes no arguments — it starts `lastUsed` (its description is required: an empty last-used description returns `no description on file (start once from the UI)`), else the first client's first project; `stop`/`pause`/`resume` return `not running` / `not paused` / `already paused` as applicable; `toggle` = start when idle, else pause/resume |
