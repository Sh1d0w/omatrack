# Invoices

`views/InvoicesView.qml` — the dashboard's **Invoices** tab. A paginated
table of generated invoices (newest first), a client filter, and a
**Generate invoice** action that opens a centered form card before
generating.

## The table

- **Rows** — `InvoiceRow`: `INV-0001 · Client name` (bold),
  `from → to · created YYYY-MM-DD` (muted), the **total** with the
  configured currency, and an **Open** action. Clicking anywhere on the
  row opens the file: `service.openPath(path)` =
  `Quickshell.execDetached("xdg-open", path)` — the system handler, since
  this runtime has no QtWebEngine.
- **Client filter** — the top dropdown, default **All** (`""` shows every
  invoice); a concrete client narrows the table to that client's
  invoices. Filtering is QML-side over `service.invoices` (the helper
  records every invoice in state — see below), paginated with the shared
  `PaginationBar` (fixed page size 15).
- **Empty state** — a centered `EmptyMessage` in the table's viewport:
  "No invoices" (none generated yet) or "No invoices for this client"
  (the filter matches nothing); the pager shows the same text.

## Generating (the form card)

**Generate invoice** (pinned to the far right of the filter row, aligned
to the dropdown's shared bottom edge) opens a `CardOverlay` card — the
same modal language and dismissal contract as the Clients/Projects add
cards (scrim click or Esc discards):

- **Range** — `From` / `To` date fields (`YYYY-MM-DD`), defaulting to
  **today → today** when the card opens. The helper demands both bounds,
  and the card validates before calling it (empty bounds →
  "Pick a billing range (from and to)"), so the "requires --from and
  --to" error cannot fire from the UI.
- **Client** — dropdown over all clients (no "All" option: an invoice is
  always for exactly one client), defaulting to the table's filtered
  client when one is picked, else the first client.
- **Generate** — `service.makeInvoice(clientId, from, to)`. On success
  the card closes, the filter follows the invoice's client (the new row
  is first — the helper prepends), the page resets to the first, and an
  `Invoice INV-0001 generated` flash runs next to the pager.

No project filter: all of the client's projects in range are invoiced,
one line each.

## Generation (helper side)

`invoice --client-id c_… --from YYYY-MM-DD --to YYYY-MM-DD [--out PATH]`:

1. Selects the client's **billable** entries with start in range. If
   none: error `no billable entries in range` (nothing is written, the
   number is not consumed).
2. Groups by project name (sorted); per project:
   `hours = round(seconds/3600, 2)`, `amount = round(hours × hourlyRate, 2)`.
3. `subtotal = round(Σ amounts, 2)`;
   `tax = round(subtotal × taxRate/100, 2)`;
   `total = round(subtotal + tax, 2)`.
4. Number: `numberPrefix + str(nextNumber).zfill(4)` → e.g. `INV-0001`;
   `nextNumber` is **incremented and persisted** in settings.
5. Writes an HTML invoice to
   `~/Downloads/<number>_<from>_<to>.html` — the user's Downloads folder,
   the same destination as exports (`--out` for a custom path).
6. **Records the invoice in state** — prepended to the `invoices` array
   (newest first):
   `{ id, number, clientId, client, from, to, seconds, subtotal, tax,
   total, path, createdAt }`. This is what feeds the tab's table (shipped
   in the state view like clients/projects); the HTML file stays the
   document of record.

Settings used: `currency`, `hourlyRate`, and the `invoice` block
(`companyName`, `companyAddress`, `taxRate`, `numberPrefix`, `nextNumber`,
`footer`) — see [settings.md](settings.md).

The HTML document: the company block (only what is configured — name
and/or address; omitted entirely when neither is set), **Bill To**
(client name), **Period** (range), **Issued** (today), an invoice number
heading, a line table (Project / Hours / Rate / Amount), a tfoot
(Subtotal, Tax (`<taxRate>%`), **Total**, currency from settings), and
the optional footer line. Self-contained, monospace, no external assets.

Regenerating for the same range produces the next number (numbers are
never reused; to redo, delete the file — the state entry stays).

## CLI

```sh
python3 timetrack.py invoice --client-id c_ab12cd34ef56 --from 2026-08-01 --to 2026-08-31
# response: { ok, path, number, client, period, lines: [{project, hours, amount}],
#             subtotal, tax, total, state }
```
