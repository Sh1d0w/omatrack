# Quattro Time Tracker

An [Omarchy](https://omarchyplugins.com/) Quattro shell plugin for time
tracking: a live timer in the bar, a click-to-open quick-start popup, and a
full management dashboard (entries, clients, projects, reports, invoices,
settings). Data lives in one JSON file managed by a single-writer
`python3` helper — no database, no polling, no extra processes.

## Features

- **Bar widget** (right section) — current task (the entry's description, or
  the client) and live elapsed time; idle shows a play glyph. Clicking opens
  the popup.
- **Popup** — pause/start with the selected task, a "next task" form with
  the **last used client/project pre-selected**, and a **Dashboard**
  button.
- **Dashboard** (real toplevel window, 7 tabs):
  - *Timer* — live hero, start/pause, next-task form, manual entry form.
  - *Entries* — filterable, paginated list; add / edit / delete.
  - *Clients* & *Projects* — CRUD with referential-integrity guards.
  - *Reports* — group by day / client / project over a date interval,
    export to **CSV** or **HTML**.
  - *Invoices* — billable entries for one client + range → numbered HTML
    invoice at the configured hourly rate.
  - *Settings* — currency, hourly rate, invoice identity + numbering.
- **Performant by design** — the only per-second work is one `SystemClock`
  tick in QML while a timer runs; entries are paginated (50/page); reports
  are computed in the helper, not in QML; exports are files opened with the
  system handler (no QtWebEngine — unavailable in this runtime).

## Install

Requirements: Omarchy with the Quattro shell, `python3` (stdlib only),
`xdg-open`.

```sh
git clone <this-repo> ~/src/omarchy-timetrack && cd ~/src/omarchy-timetrack
bash scripts/install.sh
omarchy plugin enable io.github.sh1d0w.timetrack --section right
```

`scripts/install.sh` copies the runtime files (manifest + QML + helper +
`components/` + `views/`) into `~/.config/omarchy/plugins/
io.github.sh1d0w.timetrack/` (override the base dir with
`OMARCHY_PLUGINS_DIR`). The plugin registry forbids symlinks, so the
installed copy is the source of truth at runtime — **re-run
`install.sh` after every change**, then `omarchy restart shell` if a
`Service.qml` change does not take effect.

## Usage

- **Bar** — click the widget for the popup; `pause`/`start` the task; open
  the Dashboard.
- **Dashboard** — `omarchy-shell shell toggle io.github.sh1d0w.timetrack`
  (optionally with `'{"tab":"entries"}'`; tab ids: `timer`, `entries`,
  `clients`, `projects`, `reports`, `invoices`, `settings`).
- **IPC / CLI** — `omarchy-shell timetrack start|stop|toggle|status|ping`
  drives the timer from anywhere; `python3 timetrack.py <command>` exposes
  everything else (see [docs/settings.md](docs/settings.md)).

## Data & privacy

All data is local: `~/.local/state/omarchy/timetrack/state.json`
(`XDG_STATE_HOME` honored), written atomically under an exclusive flock.
No network, no telemetry. Delete the state file to start over.

## Development

Repo layout, architecture, and the per-feature docs are in
[docs/](docs/) — [overview](docs/overview.md),
[architecture](docs/architecture.md), [bar widget](docs/bar-widget.md),
[popup](docs/popup.md), [dashboard](docs/dashboard.md),
[entries](docs/entries.md), [clients & projects](docs/clients-projects.md),
[reports & export](docs/reports-export.md),
[invoices](docs/invoices.md), [settings & CLI](docs/settings.md).

The helper test suite: `bash tests/helper_test.sh` (uses a throwaway
`XDG_STATE_HOME`; 58 checks).

## License

MIT — see [LICENSE](LICENSE).
