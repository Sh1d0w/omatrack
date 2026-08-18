# Invoices

`views/InvoicesView.qml` — the dashboard's **Invoices** tab. Turns one
client's billable entries over a date range into a numbered HTML invoice.

## The form

- **Range** — the shared `DateRangeBar` (same presets/semantics as Entries;
  matches entries by **start**, local calendar, inclusive).
- **Client** — dropdown over all clients (no "all" option: an invoice is
  always for exactly one client). **Generate invoice** is enabled only once
  a client is picked.
- No project filter: all of the client's projects in range are invoiced,
  one line each.

## Generation (helper side)

`invoice --client-id c_… --from YYYY-MM-DD --to YYYY-MM-DD [--out PATH]`:

1. Selects the client's **billable** entries with start in range. If none:
   error `no billable entries in range` (nothing is written, the number is
   not consumed).
2. Groups by project name (sorted); per project:
   `hours = round(seconds/3600, 2)`, `amount = round(hours × hourlyRate, 2)`.
3. `subtotal = round(Σ amounts, 2)`;
   `tax = round(subtotal × taxRate/100, 2)`;
   `total = round(subtotal + tax, 2)`.
4. Number: `numberPrefix + str(nextNumber).zfill(4)` → e.g. `INV-0001`;
   `nextNumber` is **incremented and persisted** in settings.
5. Writes an HTML invoice to
   `<stateDir>/invoices/<number>_<from>_<to>.html` (or `--out`).

Settings used: `currency`, `hourlyRate`, and the `invoice` block
(`companyName`, `companyAddress`, `taxRate`, `numberPrefix`, `nextNumber`,
`footer`) — see [settings.md](settings.md).

The HTML document: company name/address (or "(company name not set)"),
**Bill To** (client name), **Period** (range), **Issued** (today), an
invoice number heading, a line table (Project / Hours / Amount), a tfoot
(Subtotal, Tax (`<taxRate>%`), **Total**, currency from settings), and the
optional footer line. Self-contained, monospace, no external assets.

## The result card

On success the tab shows:

- `Invoice INV-0001 generated`
- `Total 1234.56 EUR` (currency from settings)
- the file path (middle-elided)
- **Open file** → `service.openPath(path)` = `Quickshell.execDetached(
  "xdg-open", path)` — the system handler, since this runtime has no
  QtWebEngine.

Regenerating for the same range produces the next number (numbers are never
reused; to redo, delete the file — the state only remembers `nextNumber`).

## CLI

```sh
python3 timetrack.py invoice --client-id c_ab12cd34ef56 --from 2026-08-01 --to 2026-08-31
# response: { ok, path, number, client, period, lines: [{project, hours, amount}],
#             subtotal, tax, total, state }
```
