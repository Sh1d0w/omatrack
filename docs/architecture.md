# Architecture

## Channels

The shell is one long-running Quickshell process. The plugin runs in-process
(unsandboxed); `timetrack.py` is the only out-of-process piece, spawned per
action and never kept alive.

```mermaid
flowchart LR
  subgraph shell["omarchy-shell (one Quickshell process)"]
    B[BarWidget] --> S["Service (headless singleton)"]
    P[Popup] --> S
    D[Dashboard window] --> S
    S -->|serviceFor| B
  end
  S -->|Process, serialized queue| H["timetrack.py (python3 stdlib)"]
  H -->|fcntl.flock + atomic replace| F[("~/.local/state/omarchy/timetrack/state.json")]
  CLI[("user CLI: python3 timetrack.py …")] --> H
  FV[FileView on state.json] -->|external edit → reload| S
```

## The single-writer rule

Every mutation — UI or CLI — goes through `timetrack.py`. QML never writes the
state file. The helper:

- takes an exclusive `fcntl.flock` on `state.json`'s sibling `.lock` for
  read-modify-write (shared lock for pure reads),
- writes atomically: `mkstemp` in the same directory → `fsync` → `os.replace`,
- prints exactly one JSON line on stdout:
  `{"ok": true, ...}` (exit 0) or `{"ok": false, "error": "<msg>"}` (exit 1).

`Service.qml` serializes its own helper calls: one `Process` object, a
`_queue` of pending `[args, callback]` pairs, and `_pending` for the in-flight
call. A `FileView` on `state.json` reloads the view when the file changes
while no helper run is in flight — so edits made from the CLI appear in the
UI without any polling.

## State file

Location: `$XDG_STATE_HOME/omarchy/timetrack/` (default
`~/.local/state/omarchy/timetrack/`):

```
state.json    the state (below)
.lock         flock file (never read as data)
invoices/     generated invoice HTML
exports/      generated CSV/HTML timesheets
```

`state.json` (version 1):

```json
{
  "version": 1,
  "settings": {
    "currency": "EUR",
    "hourlyRate": 0,
    "invoice": {
      "companyName": "", "companyAddress": "", "taxRate": 0,
      "numberPrefix": "INV-", "nextNumber": 1, "footer": ""
    }
  },
  "clients":  [{ "id": "c_<hex12>", "name": "Acme", "createdAt": "<utc iso>" }],
  "projects": [{ "id": "p_<hex12>", "clientId": "c_…", "name": "Landing page" }],
  "entries": [{
    "id": "e_<hex12>", "clientId": "c_…", "projectId": "p_…",
    "description": "Hero section", "billable": true,
    "start": "2026-08-18T08:00:00+00:00",
    "end":   "2026-08-18T09:30:00+00:00",
    "seconds": 5400
  }],
  "active": null
}
```

- Timestamps are **UTC ISO-8601, second precision**. Local time is used only
  where a command documents it (manual-entry date/time, day totals, date-only
  range bounds).
- `active` is an entry without `end`/`seconds` while a timer runs — it is
  written to disk **immediately on start**, which is what makes a running
  timer survive shell restarts. While paused it additionally carries
  `paused: true` and `pauseStart`; finished pause segments bank into
  `pausedSeconds` (old records normalize to `false`/`0`/`null`).
- IDs: `c_`/`p_`/`e_` + 12 hex chars of `uuid4`.

## What QML holds (the "view")

Helper mutation responses and `init`/`state` return a compact view — state
minus the entries array, plus:

- `lastUsed` — the most recently ended entry (or the active task): the
  popup's pre-selected defaults,
- `daySeconds` / `dayBillableSeconds` — local-today totals,
- `entryCount` — total number of entries (never the entries themselves).

Entries reach QML only in pages: `entries --offset N --limit N` (the UI
passes the global `pageSize` setting, default 50). The full entries array
never enters the process.

## The 1s tick

`Service.qml` contains the plugin's only periodic source:

```qml
SystemClock { precision: SystemClock.Seconds; enabled: root.running }
```

It is a C++ clock (no JS `Timer`, no process, no disk) and is **disabled
while idle**, so the idle state has zero churn. `elapsedSeconds` is the
working time: `floor(now − active.start) − pausedSeconds − the in-flight
pause segment` (that last term is 0 unless paused, in which case the value
is frozen). The bar, popup and dashboard chip all bind to `elapsedLabel`.

## Timer semantics

- `start` requires a non-blank `--description` (client and project are
  always required) and persists `active` at once (see above).
- **Pause** sets `active.paused = true` and `active.pauseStart = now`; no
  time accrues while paused (the bar/popup/dashboard labels freeze).
  **Resume** banks `now − pauseStart` into `active.pausedSeconds` and clears
  the flags. Both reject themselves (`timer is already paused` /
  `timer is not paused`) and reject when idle.
- **Stop** closes the entry: `end = now` (or `--at`), and the stored
  duration excludes all pause segments. Stopping while paused closes at the
  pause moment (the open segment is banked first).
- `stop` accepts an `--at` ISO override (naive = UTC) for corrections.
- Duration is `max(0, int(end − start) − pausedSeconds)` seconds; sub-second
  usage is 0.

## Hot reload vs. shell restart

- Saving any file under `~/.config/omarchy/plugins/` hot-reloads the shell's
  QML: bar widget, popup, dashboard, views update in place.
- **Exception:** a changed `Service.qml` may not reload an already-running
  service instance. `omarchy restart shell` is the reliable path — and it is
  also the restart-resilience test, since a running timer is on disk and
  comes back on load (`Service.Component.onCompleted → init → applyView`).

## Performance budget

| Source            | Cost while idle | Cost while a timer runs |
|-------------------|-----------------|--------------------------|
| QML polling       | none (no `Timer` loops anywhere) | none |
| `SystemClock`     | disabled        | one 1s C++ tick → relabel (no-op while paused) |
| `timetrack.py`    | not running     | not running (elapsed is computed in QML) |
| disk I/O          | none            | none |
| `FileView` watch  | kernel inotify, no work | same |

The helper runs only on user actions (start/pause/resume/stop/mutate/query/export/invoice),
typically <50 ms each.
