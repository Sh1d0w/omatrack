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
   form, step 6).
3. **Today by client** — the daily overview: one row per client with
   time today, sorted by time descending (details below). Hidden when
   no client has time yet — running task included.
4. **`Next task` header** — the section label only. Hidden while a task
   runs (paused included): there is no next task to line up until it
   stops.
5. **Next-task form** — `TaskForm` (client, project, description,
   billable; last-used client/project/billable pre-selected, description
   starts empty and is required).
   **Idle-only:** hidden while a task runs — paused included — and
   returns only when the task stops.
6. **Start** — below the form it starts from, `active` only when
   `taskForm.valid` (re-checked on click: client + project set,
   non-blank description). Idle only, same visibility rule as the form.
7. **Status line** — the service's `lastError`, red, word-wrapped.

## Today by client

The quick daily overview, between the primary action and the
`Next task` section. A `Today by client` header plus one row per client
with time today: a status dot, the client name (left), and the time
(`fmtDur`, right); rows sort by time, descending.

- The logged seconds come from the state view's `dayByClient`
  (`clientId → seconds`, local today only) computed in `omatrack.py`'s
  `build_view` next to `daySeconds`. The **live** part is QML-side:
  `Service.qml`'s `clientDay` folds the running timer's `elapsedSeconds`
  into the active client's row, so that row grows with the 1s tick while
  a task runs, freezes while paused, and the active client appears even
  before its first stop.
- The running client's row is accented (dot, name, duration); other
  rows are muted. The whole section is hidden while no client has time
  today — an untouched day shows nothing.

## Keyboard

- `inputActive` is true while a `TaskForm` control owns the keys
  (focused field or open dropdown) — the window's Esc then goes to the
  control, not the window.
