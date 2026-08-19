# Clients & projects

`views/ClientsView.qml` and `views/ProjectsView.qml` - CRUD for the two
reference tables. Both are paginated at the bottom by the shared
`PaginationBar` (`components/PaginationBar.qml`); pagination is **QML-side
slicing** (`service.clients.slice(…)` / `service.projects.slice(…)`), because the dropdowns need the full
arrays in the service anyway.

## Clients

- **Heading** — the "Clients" title + the muted one-liner, like the
  other tabs, plus a **`+`** button (tooltip "Add client") on the title
  row, far right.
- **Table** — each row is a `ClientRow` (`components/ClientRow.qml`): the
  client name (bold) with `N projects · added YYYY-MM-DD` (muted) below
  it, and **Edit** / **Del** on the right. Clicking anywhere on the row
  (or **Edit**) opens the edit card; **Del** asks for confirmation.
- **Add** — the **`+`** button in the heading row (far right, tooltip
  "Add client") opens a centered 420px `CardOverlay` (the shared
  card-on-scrim modal, same as the edit card) with a single `Client name`
  field, focused on open.
  **Add client** or **Enter** commits (non-empty) →
  `service.addClient(name)`. Scrim click or **Esc** discards (Esc via the
  view's `handleKey`, routed by the dashboard's key gate). New clients
  append at the end, so a successful add jumps the list to the last page.
- **Rename** — the edit card: a centered 420px `CardOverlay` (the shared
  card-on-scrim modal, same as the Entries edit card) with a single
  `Client name` field pre-filled with the current name. **Save** or
  **Enter** commits (only when non-empty and actually changed) →
  `service.updateClient(id, name)`. Scrim click or **Esc** discards
  (Esc via the view's `handleKey`, routed by the dashboard's key gate).
- **Status line** — right of the bottom pager: an accent flash
  ("Client added" / "Client saved", 2 s) and the red `lastError`
  (duplicate-name refusal, delete block with counts).
- **Delete** — **Del** → the window-level confirm dialog (see
  [dashboard.md](dashboard.md)) with "Delete this client? Its projects
  and entries must already be gone." → `service.deleteClient(id)`. The
  helper **refuses** when the client is still referenced; the red
  `lastError` line shows the count.
- The bottom pager page-navigates the client list (`prevPage`/`nextPage`
  step by one fixed page of 15).
- While the add card or the edit card is open, the view reports
  `inputActive` so the window's Esc goes to the card (which closes it)
  instead of the window. The delete dialog needs no view-side plumbing:
  the dashboard owns it and knows when it is open.

## Projects

One flat paginated table (no per-client grouping), narrowed by the top
`Client` picker.

- **Heading** — the "Projects" title + the muted one-liner, like the
  other tabs, plus a **`+`** button (tooltip "Add project") on the title
  row, far right.
- **Table** — each row is a `ProjectRow` (`components/ProjectRow.qml`):
  the project name (bold) with the owning client (muted) below it, and
  **Edit** / **Del** on the right. Clicking anywhere on the row (or
  **Edit**) opens the edit card; **Del** asks for confirmation.
- **Filter** — the labeled `Client` picker (own row under the heading,
  default **All clients**) narrows the table to one client's projects;
  picking a client resets the pager to page one.
- **Add** — the **`+`** button in the heading row (far right, tooltip
  "Add project") opens a centered 420px `CardOverlay` with a
  `Project name` field (focused on open) and a labeled `Client` picker.
  The picker defaults to the filtered client when one is selected, else
  the first client. **Add
  project** or **Enter** commits (name non-empty, client picked) →
  `service.addProject(clientId, name)`. Scrim click or **Esc** discards
  (Esc via the view's `handleKey`, routed by the dashboard's key gate).
  A successful add filters the table to the picked client (so the new
  row is visible) and jumps to the last page (the helper appends).
- **Edit / rename / move** — the edit card: a centered 420px
  `CardOverlay` with a `Project name` field and a labeled `Client`
  picker, both pre-filled. **Save** or **Enter** commits (only when
  non-empty and actually changed) → `service.updateProject(id, name,
  clientId)`. The picker doubles as **move between clients**: uniqueness
  is checked against the **target** client (so a project may join a
  client where no same-named project exists); the same move is still
  available from the CLI (`project-update --id p_… --client-id c_…`).
  Scrim click or **Esc** discards (Esc via the view's `handleKey`,
  routed by the dashboard's key gate).
- **Status line** — right of the bottom pager: an accent flash
  ("Project added" / "Project saved", 2 s) and the red `lastError`
  (duplicate-name refusal, delete block with counts).
- **Delete** — **Del** → the window-level confirm dialog (see
  [dashboard.md](dashboard.md)) with "Delete this project? Entries that
  reference it must already be gone." → `service.deleteProject(id)`;
  refused by the helper while entries reference it.
- While a picker popup, an add/edit field, or an add/edit card is open,
  the view reports `inputActive` so the window's Esc goes to the card
  (which closes it) instead of the window. The delete dialog needs no
  view-side plumbing: the dashboard owns it and knows when it is open.

## Data rules (helper side)

| Command            | Rule |
|--------------------|------|
| `client-add --name` | name non-empty after trim; **case-insensitive duplicate** (`name.strip().lower()`) rejected: `client already exists` |
| `client-update --id [--name]` | same duplicate check against other clients |
| `client-delete --id` | blocked: `client-delete blocked: N projects, M entries reference this client` |
| `project-add --client-id --name` | client must exist; name unique **per client** (case-insensitive) |
| `project-update --id [--name] [--client-id]` | target client must exist; name unique within the target client; enables moving a project between clients |
| `project-delete --id` | blocked: `project-delete blocked: N entries reference this project` |

There is no cascade delete anywhere: the referential rules are the
integrity model. To delete a client, delete its entries, then its projects,
then the client.

IDs are `c_<hex12>` / `p_<hex12>` (uuid4); a client's `createdAt` is the UTC
timestamp of creation.
