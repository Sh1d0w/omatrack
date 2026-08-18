# Timer tab

`views/TimerView.qml` — the dashboard's **Timer** tab: live hero, timer
controls, and the next-task form. Shares `TaskForm` with the bar popup and
the Entries tab. Manual entries live on the **Entries** tab
([entries.md](entries.md)).

## Layout (top → bottom)

1. **Hero** — the elapsed time (`displayLarge`; dimmed while paused or
   stopped), the task name (`Client — description`, `No active timer`
   when idle), and a caption: running/paused →
   `paused? · description? · started HH:mm · billable/non-billable`;
   idle → `Today HH:MM · billable HH:MM`.
2. **Primary action** — running: `Pause` + bordered `Stop`; paused:
   `Resume` + `Stop`. Nothing here when idle (Start lives below the
   form, step 5).
3. **`Next task` header** — the section label only. Hidden while a task
   runs (paused included): there is no next task to line up until it
   stops.
4. **Next-task form** — `TaskForm` (client, project, description,
   billable; last-used values pre-selected, description required).
   **Idle-only:** hidden while a task runs — paused included — and
   returns only when the task stops.
5. **Start** — below the form it starts from, `active` only when
   `taskForm.valid` (re-checked on click: client + project set,
   non-blank description). Idle only, same visibility rule as the form.
6. **Status line** — the service's `lastError`, red, word-wrapped.

## Keyboard

- `inputActive` is true while a `TaskForm` control owns the keys
  (focused field or open dropdown) — the window's Esc then goes to the
  control, not the window.
