# Quick-start popup

`Popup.qml` — the anchored panel that opens on left-click of the bar widget.
One panel covers the whole "do I start or stop something" decision: status,
start/pause/resume/stop, the new-task form, and a dashboard shortcut.

## Structure (top → bottom)

1. **Status row** — an 8px dot (accent while running, dim while paused,
   dimmest when idle), the title (`Acme — Hero section`, or the description
   alone, or the client alone, or `-`; `No active timer` when idle) and the
   caption (`01:02:03 · billable` while running; `01:02:03 · paused ·
   billable` while paused; `Today 04:12` or `Start a task below` when idle).
2. **`New task` section** — a `New task` header, a `TaskForm`
   (client/project/description/billable, see below), and a full-width
   `Start` **below the form**, active only when `formReady` (client,
   project and a non-blank description). The whole section is
   **idle-only**: it disappears while a task runs — paused included — and
   returns when the task stops.
3. **Primary action** — running: `Pause` (→ `service.pauseTask()`) beside
   a bordered `Stop` (→ `service.stopTask()`). Paused: `Resume` (→
   `service.resumeTask()`) + `Stop`. Nothing here when idle (Start lives
   below the form, item 2).
4. **Footer** — `Today HH:MM` on the left, `Dashboard…` button on the right.
5. **Error line** — the service's `lastError`, red, word-wrapped (e.g. a
   failed start).

## The new-task form

`TaskForm` (`components/TaskForm.qml`) is the shared four-field form also
used by TimerView. The popup does not mirror its values:

- **Pre-selection (requirement):** `taskForm.applyDefaults()` seeds
  client and project from the service's `lastUsed` (the most recently ended
  entry, or the active task) — falling back to the first client and first
  project of that client — and the last billable flag when present. The
  description is deliberately seeded **empty**: every started task gets a
  fresh description, never a copy of the last one. `TaskForm` self-seeds
  when the service is injected (its `onServiceChanged`; a Loader's
  `onLoaded` runs after `onCompleted`), and the popup re-arms the seeding on
  `opened` (via `Qt.callLater`, so it wins over focus initialization).
  Seeding never overwrites a value the user edited.
- **Persistence across open/close:** the `TaskForm` instance lives with the
  popup, so a half-filled form survives a stray Esc.
- **Mandatory description:** `taskForm.valid`
  (`clientId !== "" && projectId !== "" && description.trim() !== ""`) gates
  the Start button. `startFromForm()` re-checks and sets
  `service.lastError` to `"Pick a client and project"` or
  `"Add a task description"` as appropriate; the helper itself also rejects a
  blank/whitespace description (`description is required`).
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
