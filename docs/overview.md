# Overview

Quattro Time Tracker is an Omarchy shell plugin for tracking billable and
non-billable work time per client and project. It shows a live timer in the
bar, offers a one-click quick-start popup, and a dashboard window for
managing entries, clients, projects, reports, invoices, and settings.

Plugin id: `io.github.sh1d0w.timetrack`.

## The three plugin kinds

One plugin, three kinds (declared in `manifest.json`):

| Kind         | File            | What it is                                             |
|--------------|-----------------|--------------------------------------------------------|
| `bar-widget` | `BarWidget.qml` | Right-section label: current task + elapsed, or ▶ idle |
| `service`    | `Service.qml`   | Headless singleton: state, helper channel, IPC         |
| `panel`      | `Dashboard.qml` | Toplevel dashboard window (7 tabs)                     |

Because both `bar-widget` and `panel` kinds are present, the shell's
summon/toggle routing (`shell.qml`) targets the **panel** entry:
`omarchy-shell shell toggle io.github.sh1d0w.timetrack` opens the dashboard,
not the popup — there is no CLI to open the bar popup, which opens only by
clicking the bar widget.

## File map

```
manifest.json        kinds, category, defaultSection: right
Service.qml          headless engine (see architecture.md)
BarWidget.qml        bar label + popup host          (bar-widget.md)
Popup.qml            anchored quick-start popup      (popup.md)
Dashboard.qml        toplevel window, 7 tabs         (dashboard.md)
timetrack.py         state engine + CLI, single writer
components/          TaskForm, EntryForm, DateRangeBar, EntryRow
views/               TimerView, EntriesView, ClientsView, ProjectsView,
                     ReportsView, InvoicesView, SettingsView
```

## Quick start

```sh
# from this repo
bash scripts/install.sh
omarchy plugin enable io.github.sh1d0w.timetrack --section right
```

Then:

- Click the ▶ in the right bar section → quick-start popup.
- Start a client + project first (via the popup's form after creating them in
  the dashboard, or via the CLI):

  ```sh
  python3 timetrack.py client-add --name "Acme"
  python3 timetrack.py project-add --client-id c_XXXXXXXXXXXX --name "Landing page"
  ```

- Open the dashboard: `omarchy-shell shell toggle io.github.sh1d0w.timetrack`
  (or the popup's Dashboard button).

## Feature index

| Feature                                   | Doc                       |
|-------------------------------------------|---------------------------|
| Architecture, state, performance budget   | [architecture.md](architecture.md) |
| Bar widget (right section)                | [bar-widget.md](bar-widget.md)     |
| Quick-start popup                         | [popup.md](popup.md)               |
| Dashboard window (tabs, keyboard)         | [dashboard.md](dashboard.md)       |
| Entries (filters, add/edit/delete)        | [entries.md](entries.md)           |
| Clients & projects (CRUD rules)           | [clients-projects.md](clients-projects.md) |
| Reports & CSV/HTML export                 | [reports-export.md](reports-export.md) |
| Invoices                                  | [invoices.md](invoices.md)         |
| Settings & CLI                            | [settings.md](settings.md)         |
