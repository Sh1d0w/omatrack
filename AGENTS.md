# AGENTS.md — OmaTrack

## Project summary

An Omarchy (Quattro shell) plugin for time tracking: a live bar widget, a
quick-start popup, and a full management dashboard (entries, clients,
projects, reports, invoices, settings).

- Plugin id: `io.github.sh1d0w.omatrack` (third-party ids must not start with `omarchy.`).
- Developed in this repo. The **installed copy** is what runs: the plugin
  registry forbids symlinks, so `scripts/install.sh` copies the runtime files
  into `~/.config/omarchy/plugins/io.github.sh1d0w.omatrack/`.

## Layout

```
manifest.json        plugin manifest (bar-widget + service + panel kinds)
Service.qml          headless in-process engine (state, helper channel, IPC)
BarWidget.qml        right-section bar label + popup host
Popup.qml            anchored quick-start popup
Dashboard.qml        toplevel dashboard window (FloatingWindow)
omatrack.py         state engine + CLI (python3 stdlib only; single writer)
components/          shared UI: TaskForm, EntryForm, DateRangeBar, EntryRow,
                     ClientRow, ProjectRow, CardOverlay, PaginationBar
views/               dashboard tabs: Timer, Entries, Clients, Projects,
                     Reports, Invoices, Settings
tests/helper_test.sh shell tests for omatrack.py (throwaway XDG_STATE_HOME)
docs/                one file per feature (see rule below)
scripts/install.sh   copies runtime files into the plugin dir
```

## Runtime contract

- The shell is one long-running Quickshell process. Plugins run **in-process**,
  unsandboxed. Never start a second Quickshell.
- `Service.qml` is a `service` kind: a headless singleton, accessed from the
  bar widget via `bar.shell.serviceFor("io.github.sh1d0w.omatrack")` and
  injected into the dashboard (the root declares `property var service`).
- All state mutations go through `omatrack.py` — the **single writer** of
  `~/.local/state/omarchy/omatrack/state.json` (atomic tmp + `os.replace`,
  `fcntl.flock`). QML never writes the file directly.
- The dashboard is a `panel` kind rendered by the shell's panel loader as a
  `FloatingWindow`. Summon: `omarchy-shell shell toggle io.github.sh1d0w.omatrack '{"tab":"entries"}'`.
  The bar popup opens only on bar click (the shell routes summon/toggle to the
  panel when both kinds are present).

## Dev loop

```sh
bash tests/helper_test.sh     # data engine (must PASS)
bash scripts/install.sh       # copy into the plugin dir
omarchy plugin validate ~/.config/omarchy/plugins/io.github.sh1d0w.omatrack
qmllint -I /usr/share/omarchy/shell <file.qml>   # every QML file
```

After editing: saving a file under `~/.config/omarchy/plugins/` hot-reloads it.
**Caveat:** a changed `Service.qml` may not reload a running service — run
`omarchy restart shell` when service behavior looks stale.

Visual verification: `omarchy capture screenshot`, then read the PNG.

## Rule

**Every feature must be documented in `docs/`. When you add or change a
feature, add or update its doc in the same change.**

## Conventions

- No code duplication. `components/` (`TaskForm`, `EntryForm`, `DateRangeBar`,
  `EntryRow`, `ClientRow`, `ProjectRow`, `CardOverlay`, `PaginationBar`) and
  the shell's `qs.Ui` kit are the shared pieces; views compose them instead
  of re-implementing.
- `omatrack.py`: python3 **stdlib only**, one JSON line per run
  (`{"ok": true, ...}` / `{"ok": false, "error": "..."}`), timestamps as UTC
  ISO-8601 seconds.
- No polling in QML. One 1s C++ tick (`SystemClock`) and only while a timer
  runs; the helper process exists only during an action.
- No symlinks anywhere under the plugin folder. No `omarchy.*` plugin id.
- Entries are paginated in the UI (limit 15); the full entries array never
  enters QML (mutation responses carry a compact "view" instead).
- This runtime has **no QtSql, QtGraphicalEffects, or QtWebEngine** — exports
  and invoices are HTML/CSV files opened with `xdg-open`.
