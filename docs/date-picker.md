# Date picker & range bar

Two shared components in `components/`. `DateRangeBar` (presets + manual
pickers) is the range filter of the Entries tab; Reports reuses it with
the picker row hidden (`showPickers: false`, presets only). Bare
`DatePicker`s are used in the invoice generate card (From/To) and the
manual-entry form (start date).

## `DatePicker.qml`

A read-only date field: a Dropdown-style trigger showing `YYYY-MM-DD`
(muted placeholder when empty) that opens a **month-grid calendar popup**
below.

- One month at a time, Monday-first weeks, 42 cells so the popup height is
  constant. Out-of-month spillover days render muted; the current day gets
  an accent ring; the picked day gets the accent fill.
- Month navigation via `◀`/`▶`; footer shortcuts **Today** and **Clear**
  (Clear empties the bound — an open range bound).
- The host owns the value: the component only displays `date` and emits
  `changed(dateStr)`; the host writes the new value back through its own
  binding, so the binding never breaks.
- Keyboard: **Enter**/**Space**/**Down** opens from the trigger; while
  open, **Left/Right** move the cursor a day, **Up/Down** a week,
  **Enter** selects, **Esc** or a press outside closes (modal popup,
  `CloseOnPressOutside`).
- `popupOpen` is exposed so the host view can report `inputActive: true`
  and keep the dashboard's window-level key catcher (Esc closes the
  window) blocked while the picker owns the keyboard.

## `DateRangeBar.qml`

Two rows:

1. Six presets: `Today`, `Yesterday`, `7 days`, `This month`, `Last
   month`, `All` — computed on the **local calendar** via
   `service.localDateStr` (one implementation of the date helpers).
2. `From` / `To` `DatePicker`s (row hidden with `showPickers: false`).

Emits `changed(from, to, preset)` with `preset ""` when a date is picked
by hand (a hand pick breaks the active preset). `currentPreset` drives
the highlighted preset button. Date-only ranges are inclusive and match
entries whose **start** falls in the local-day range — the helper resolves
`from`/`to` to local `00:00:00` / `23:59:59` (see
[entries.md](entries.md)).

`fieldActive` is true while either picker popup is open; both views fold
it into their `inputActive`.

`showPickers` (default `true`) hides the manual picker row; Reports keeps
its range preset-only (manual dates are picked in Entries / invoices).
The root sizes itself to its natural width (`naturalWidth` = the wider
row's implicit width), so a caller can anchor it inside a wider row and
let the right side carry other controls (Reports does); the Entries view
instead stretches it with an explicit `width`. With the pickers hidden
the root's height collapses to the preset row (a `visible: false` row
would still occupy space in a `Column`).

### Layout note

The root is a `Column`, not a bare `Item`: a plain `Item` does not
propagate its children's implicit height, and the old single-row `Item`
root therefore rendered at 0 px inside the views' `Column` headers —
the bar existed in the files but was invisible. A `Column` root sizes
itself from its rows.
