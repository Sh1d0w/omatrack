# Quick-start popup

`Popup.qml` — the anchored panel that opens on left-click of the bar widget.
One panel covers the whole "do I start or stop something" decision: status,
start/pause, the new-task form, and a dashboard shortcut.

## Structure (top → bottom)

1. **Status row** — an 8px dot (accent while running, dim otherwise), the
   title (`Acme — Hero section`, or the description alone, or the client
   alone, or `-`; `No active timer` when idle) and the caption
   (`01:02:03 · billable` / `01:02:03 · non-billable` while running;
   `Today 04:12` or `Start a task below` when idle).
2. **Primary action** — one full-width `Button`: `Pause` while running
   (→ `service.stopTask()`), `Start` when idle. `Start` is only *active* when
   `formReady` (client and project both set), so it visually reflects
   validity.
3. **`New task` section** — a `TaskForm` (client/project/description/
   billable, see below).
4. **Footer** — `Today HH:MM` on the left, `Dashboard…` button on the right.
5. **Error line** — the service's `lastError`, red, word-wrapped (e.g. a
   failed start).

## The new-task form

`TaskForm` (`components/TaskForm.qml`) is the shared four-field form also
used by TimerView. The popup does not mirror its values:

- **Pre-selection (requirement):** on open, `taskForm.applyDefaults()` seeds
  client and project from the service's `lastUsed` (the most recently ended
  entry, or the active task) — falling back to the first client and first
  project of that client. Seeding is re-armed on `opened` (via
  `Qt.callLater`, so it wins over focus initialization), on service arrival,
  and on load; it never overwrites a value the user edited.
- **Persistence across open/close:** the `TaskForm` instance lives with the
  popup, so a half-filled form survives a stray Esc.
- **`formReady`** (`clientId !== "" && projectId !== ""`) gates the Start
  button; `startFromForm()` re-checks and sets
  `service.lastError = "Pick a client and project"` if incomplete.
- `billable` defaults to `true`.

## Keyboard

`PanelKeyCatcher` (via `KeyboardPanel`):

- `Esc` closes the popup — unless a form control owns the keys
  (`taskForm.keyActiveItem !== null`: a focused field or an open dropdown),
  in which case that control handles Esc (closes the dropdown / blurs).
- `Enter` / `Return` / `Space` on empty focus starts the task when idle.
- `Tab` / `Shift+Tab` cycle the bar's popouts (bar-level, not in-popup).

## Service + IPC

`service` is injected by the `BarWidget` loader (alongside `anchorItem` and
`hostWidget`). `manageIpc: false`: the popup declares no IPC — the plugin's
single `IpcHandler { target: "timetrack" }` lives in `Service.qml`, so a
panel-side IpcHandler would collide with it.

## Dashboard button

`Dashboard…` calls `root.bar.shell.summon("io.github.sh1d0w.timetrack",
JSON.stringify({}))` — in-process, no process spawn — and opens the
dashboard on its default tab (timer).

## Bar shape contract

The popup is a `Panel`; the `BarWidget` forwards the bar's
`opened`/`open()`/`close()`/`toggle()` expectations here, and
`popoutSwitchClosing` / `closeForPopoutSwitch()` (mirroring
`KeyboardPanel`) let the bar treat this popup as its popout identity.
