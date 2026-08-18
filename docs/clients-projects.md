# Clients & projects

`views/ClientsView.qml` and `views/ProjectsView.qml` — CRUD for the two
reference tables. Both are flat lists (no pagination: these tables are
expected to stay small) backed by the in-service view state.

## Clients

- **Add** — top row: `New client…` field + **Add** (Enter in the field
  commits). Empty names are ignored; duplicates are rejected (see rules).
- **Rename** — each row's name is a `TextField`; **Enter commits** (only
  when non-empty and actually changed) → `service.updateClient(id, name)`.
- **Row meta** — `N projects · added YYYY-MM-DD`.
- **Delete** — **Del** → the window-level confirm dialog (see
  [dashboard.md](dashboard.md)) with "Delete this client? Its projects
  and entries must already be gone." → `service.deleteClient(id)`. The
  helper **refuses** when the client is still referenced; the red
  `lastError` line shows the count.
- While any name field is focused, the view reports `inputActive` so the
  window's Esc goes to the control, not the window. The dialog needs no
  view-side plumbing: the dashboard owns it and knows when it is open.

## Projects

Grouped by client: one section per client (client name as header). Each
section carries its own `New project for <client>…` add row **above** the
project list.

- **Add** — per client section; the client is fixed by the section.
- **Rename** — inline `TextField`, Enter commits →
  `service.updateProject(id, name, clientId)`.
- **Move between clients** — the update API takes a target `clientId`;
  uniqueness is checked against the **target** client (so a project may
  join a client where no same-named project exists). The UI's rename keeps
  the section's client; moving is available from the CLI
  (`project-update --id p_… --client-id c_…`).
- **Delete** — **Del** → the window-level confirm dialog (see
  [dashboard.md](dashboard.md)) with "Delete this project? Entries that
  reference it must already be gone." → `service.deleteProject(id)`;
  refused by the helper while entries reference it.

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
