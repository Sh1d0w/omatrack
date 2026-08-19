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
`Acme — Hero · 01:02:03 (paused)` / `Today 04:12`) binds to the service and
re-evaluates on its 1s tick (frozen while paused).

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
- **Content inset:** every tab insets its content 16px on all sides —
  the same 16px the header row insets (Timer's column uses
  `anchors.margins`, the other tabs add matching margins to their
  anchored blocks) — so no tab's content runs edge-to-edge.

## Tabs

| id         | view                    | Doc |
|------------|-------------------------|-----|
| `timer`    | `views/TimerView.qml`   | [timer.md](timer.md) |
| `entries`  | `views/EntriesView.qml` | [entries.md](entries.md) |
| `clients`  | `views/ClientsView.qml` | [clients-projects.md](clients-projects.md) |
| `projects` | `views/ProjectsView.qml` | [clients-projects.md](clients-projects.md) |
| `reports`  | `views/ReportsView.qml` | [reports-export.md](reports-export.md) |
| `invoices` | `views/InvoicesView.qml` | [invoices.md](invoices.md) |
| `settings` | `views/SettingsView.qml` | [settings.md](settings.md) |

The loader sets `item.service = root.service` and `item.dashboard = root` on
load, so views reach the engine and can call `dashboard.requestClose()` /
`dashboard.activeTab = ...`.

## Confirm dialog (window-level)

Destructive actions confirm through a **single window-level
`ConfirmDialog`** owned by the dashboard. It fills the window
(`anchors.fill: parent`, the shell-kit pattern used by the Menu and
Clipboard panels), so the card is always centered over the whole window
and the scrim covers sidebar and header alike. Views request it:

```qml
dashboard.confirmAction(message, onConfirm)
```

`onConfirm` runs after the dialog closes (scrim click, **Cancel**, or Esc).
The dialog resets on tab switch and on `open()`, so a pending confirmation
never fires for a view that is no longer loaded.

## Keyboard

The window `FocusScope` installs a `Keys.BeforeItem` key gate that sees
every key before any other handler (focused control included):

1. confirm dialog open → its `handleKey` owns Esc / ← → / Tab / Enter
   (cancel / confirm, with `selectedIndex` driving the highlight);
2. otherwise the active view's `handleKey`, if it defines one (the
 Entries edit card and manual-entry card close on Esc);
3. otherwise fall through — a window-level `PanelKeyCatcher` handles
   `Esc` (closes the window), focused controls keep their keys.

The key catcher's `blocked` is set while the confirm dialog is open or the
active view reports `inputActive` (a field/dropdown/form owns the
keyboard). Views expose only `inputActive` — there is no `dialogOpen`
contract: the dashboard knows its own dialog, and view-level overlays
report themselves through `inputActive`.

`Tab` does nothing special at window level (no popout siblings); focus
cycles within the view.

## Summon

```sh
omarchy-shell shell toggle io.github.sh1d0w.timetrack            # timer tab
omarchy-shell shell toggle io.github.sh1d0w.timetrack '{"tab":"reports"}'
```

`toggle` re-summons an existing open instance (calls `open(payloadJson)`
again → switches tab) or creates one. The bar's `Dashboard…` button uses the
same `shell.summon` path in-process.
