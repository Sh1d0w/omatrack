# Dashboard window

`Dashboard.qml` — the `panel` kind. A real toplevel `FloatingWindow`
(`implicitWidth: 1100`, `implicitHeight: 700`, minimum `860×560`, title
"Quattro — Time Tracking") managed by the shell's panel loader.

## Shell contract

The panel loader (shell.qml) instantiates the `panel` entry and injects
`shell`, `omarchyPath`, `manifest`, `barWidgetRegistry`, `pluginRegistry` —
and `service`, because the root declares `property var service`.

| Contract | Behavior |
|----------|----------|
| `open(payloadJson)` | Shows the window. Optional `{"tab": "<id>"}` pre-selects a tab; unknown/invalid ids are ignored (the current tab is kept). Then forces focus into the key catcher. |
| `close()` | Host-side close (e.g. `shell hide`): hides the window with `closingFromHost = true` so the window does **not** call back into `shell.hide`. |
| user close (titlebar X / Esc) | `requestClose()` → `shell.hide(pluginId)` → the loader drops the instance (window destroyed). |

No `keepLoaded`: the instance is created on summon and destroyed on close.
While open, the header's live chip (`Acme — Hero · 01:02:03` /
`Paused · Today 04:12`) binds to the service and re-evaluates on its 1s tick.

## Layout

```
┌──────────┬─────────────────────────────────────────────┐
│ Quattro  │ Quattro — Time Tracking  ● Acme — Hero · 0:02│
│ time     ├─────────────────────────────────────────────┤
│ tracking │                                             │
│ [Timer]  │              active tab view                │
│ [Entries]│              (Loader, fills area)           │
│ ...      │                                             │
└──────────┴─────────────────────────────────────────────┘
```

- **Sidebar (190px):** title block + one `Button` per tab (Repeater over
  `TABS`); the active tab's button is `selected`.
- **Main:** header row (title + live status chip, 56px) and a single `Loader`.
  Switching tabs **destroys the old view and loads the new one** — there is
  no per-tab state caching. All persistent state lives in the service and on
  disk, so filters resetting on tab switch is expected behavior (documented
  here, not a bug).

## Tabs

| id         | view                    | Doc |
|------------|-------------------------|-----|
| `timer`    | `views/TimerView.qml`   | [popup.md](popup.md) (shares `TaskForm`) |
| `entries`  | `views/EntriesView.qml` | [entries.md](entries.md) |
| `clients`  | `views/ClientsView.qml` | [clients-projects.md](clients-projects.md) |
| `projects` | `views/ProjectsView.qml` | [clients-projects.md](clients-projects.md) |
| `reports`  | `views/ReportsView.qml` | [reports-export.md](reports-export.md) |
| `invoices` | `views/InvoicesView.qml` | [invoices.md](invoices.md) |
| `settings` | `views/SettingsView.qml` | [settings.md](settings.md) |

The loader sets `item.service = root.service` and `item.dashboard = root` on
load, so views reach the engine and can call `dashboard.requestClose()` /
`dashboard.activeTab = ...`.

## Keyboard

A window-level `PanelKeyCatcher` owns the `FocusScope`:

- `Esc` closes the window **only when** the active view does not own the
  keys. Views expose `inputActive` (a field/dropdown is focused) and
  `dialogOpen` (a confirm dialog or form overlay is up); while either is
  true, `blocked` is set and the control/dialog handles Esc itself.
- `Tab` does nothing special at window level (no popout siblings); focus
  cycles within the view.

## Summon

```sh
omarchy-shell shell toggle io.github.sh1d0w.timetrack            # timer tab
omarchy-shell shell toggle io.github.sh1d0w.timetrack '{"tab":"reports"}'
```

`toggle` re-summons an existing open instance (calls `open(payloadJson)`
again → switches tab) or creates one. The bar's `Dashboard…` button uses the
same `shell.summon` path in-process.
