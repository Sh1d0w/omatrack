# Timer tab

`views/TimerView.qml` — the dashboard's **Timer** tab: live hero, timer
controls, the next-task form, and the manual-entry modal. Shares
`TaskForm`/`EntryForm` with the bar popup and the Entries tab.

## Layout (top → bottom)

1. **Hero** — the elapsed time (`displayLarge`; dimmed while paused or
   stopped), the task name (`Client — description`, `No active timer`
   when idle), and a caption: running/paused →
   `paused? · description? · started HH:mm · billable/non-billable`;
   idle → `Today HH:MM · billable HH:MM`.
2. **Primary action** — running: `Pause` + bordered `Stop`; paused:
   `Resume` + `Stop`. Nothing here when idle (Start lives below the
   form, step 5).
3. **`Next task` header row** — the section label and, on the opposite
   side (far right, same line — a stretching spacer pins the button to
   the row's right edge), an `Add manual entry` button that opens the
   manual-entry modal. Stays visible in every state: manual entries are
   independent of the timer, so they can be logged while a task runs.
4. **Next-task form** — `TaskForm` (client, project, description,
   billable; last-used values pre-selected, description required).
   **Idle-only:** hidden while a task runs — paused included — and
   returns only when the task stops.
5. **Start** — below the form it starts from, `active` only when
   `taskForm.valid` (re-checked on click: client + project set,
   non-blank description). Idle only, same visibility rule as the form.
6. **Status line** — the `Entry added` flash (2 s) and the service's
   `lastError`, red, word-wrapped.

## Manual-entry modal

`Add manual entry` opens a centered modal on a scrim — `CardOverlay`
(`components/CardOverlay.qml`, shared with the Entries edit card): title,
`EntryForm` (date, time, minutes, then the shared `TaskForm`), `Add
entry` and `Close`.

- `EntryForm` pre-fills once, when the service is injected
  (`defaultsToToday()`: today, current local time, 60 minutes, last-used
  client/project via `applyDefaults()`). A half-filled form survives
  close/reopen.
- `Add entry` is gated on `entryForm.valid` (well-formed date/time,
  minutes ≥ 1, client + project set); an invalid submit sets
  `lastError = "Fill in a valid manual entry"`.
- A successful add closes the modal and flashes `Entry added`.
- **Scrim click or Esc dismisses** — the same semantics as the Entries
  edit card and the window-level confirm dialog. Esc routes through the
  view's `handleKey` (the dashboard's key gate forwards it); while the
  modal is open the view reports `inputActive`, so the window key catcher
  does not swallow the keys or close the window.

## Keyboard

- `handleKey`: Esc closes the manual-entry modal when it is open.
- `inputActive` is true while a `TaskForm`/`EntryForm` control owns the
  keys (focused field or open dropdown) or while the modal is open — the
  window's Esc then closes the modal, not the window.
