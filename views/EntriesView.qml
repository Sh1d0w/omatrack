import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// Entries tab: date presets + filters, a paginated entry list (50 per
// page — the full array never enters QML), and edit/delete through a
// centered card overlay.
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null
  property string flash: ""

  // The window keyCatcher blocks while a filter control, the edit form, or
  // the edit overlay itself owns the keyboard.
  readonly property bool inputActive: clientDrop.popupOpen || projectDrop.popupOpen
    || billableDrop.popupOpen || searchField.activeFocus || rangeBar.fieldActive
    || root.editEntry !== null

  // ---- state -----------------------------------------------------------------
  property var entries: []
  property int total: 0
  property int totalSeconds: 0
  property int billableSeconds: 0
  property int offset: 0
  readonly property int limit: 50

  property string from: ""
  property string to: ""
  property string clientId: ""
  property string projectId: ""
  property string billableFilter: ""   // "" | "yes" | "no"
  property string search: ""
  property string currentPreset: "all"
  property var editEntry: null

  Timer {
    id: flashTimer
    interval: 2000
    onTriggered: root.flash = ""
  }

  Timer {
    id: searchDebounce
    interval: 300
    onTriggered: root.applyFilters()
  }

  function filterObj() {
    return {
      from: root.from,
      to: root.to,
      clientId: root.clientId,
      projectId: root.projectId,
      billable: root.billableFilter === "yes" ? 1 : (root.billableFilter === "no" ? 0 : null),
      search: root.search
    }
  }

  function applyFilters() {
    root.offset = 0
    root.queryAt(0)
  }

  function queryAt(offset) {
    if (!root.service) return
    root.service.queryEntries(root.filterObj(), offset, function(resp) {
      if (resp.ok) {
        root.entries = resp.entries
        root.total = resp.total
        root.totalSeconds = resp.totalSeconds
        root.billableSeconds = resp.billableSeconds
        root.offset = resp.offset
      } else {
        root.service.lastError = resp.error || "Query failed"
      }
    })
  }

  function nextPage() {
    if (root.offset + root.limit < root.total)
      root.queryAt(root.offset + root.limit)
  }

  function prevPage() {
    if (root.offset > 0)
      root.queryAt(Math.max(0, root.offset - root.limit))
  }

  function refreshCurrentPage() {
    root.queryAt(root.offset)
  }

  function openEdit(entry) {
    root.editEntry = entry
    var s = root.service
    if (!s) return
    // Pre-fill from the entry's local start + duration.
    editForm.dateStr = s.localDateStr(new Date(entry.start))
    editForm.timeStr = s.localTimeStr(new Date(entry.start))
    editForm.minutes = Math.max(1, Math.round(entry.seconds / 60))
    editForm.clientId = entry.clientId
    editForm.projectId = entry.projectId
    editForm.description = entry.description
    editForm.billable = entry.billable === 1 || entry.billable === true
  }

  function closeEdit() {
    root.editEntry = null
  }

  function requestDelete(entry) {
    if (!entry || !root.dashboard) return
    var id = entry.id
    root.dashboard.confirmAction("Delete this time entry?", function() {
      if (!root.service) return
      root.service.deleteEntry(id, function(resp) {
        if (resp.ok) {
          root.closeEdit()
          root.flash = "Entry deleted"
          flashTimer.restart()
          root.refreshCurrentPage()
        } else {
          root.service.lastError = resp.error || "Delete failed"
        }
      })
    })
  }

  // Window-level key gate: the dashboard forwards keys to views that define
  // handleKey. Esc closes the edit overlay (same dismissal as clicking the
  // scrim).
  function handleKey(event) {
    if (root.editEntry !== null && event.key === Qt.Key_Esc) {
      root.closeEdit()
      return true
    }
    return false
  }

  Column {
    id: topControls
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    spacing: Style.space(10)

    // ---- date presets --------------------------------------------------------
    DateRangeBar {
      id: rangeBar
      service: root.service
      from: root.from
      to: root.to
      currentPreset: root.currentPreset
      width: parent.width

      onChanged: function(f, t, preset) {
        root.from = f
        root.to = t
        root.currentPreset = preset
        root.applyFilters()
      }
    }

    // ---- filter row ----------------------------------------------------------
    Row {
      spacing: Style.space(8)

      Dropdown {
        id: clientDrop
        label: "Client"
        showLabel: true
        width: Style.space(170)
        value: root.clientId
        options: {
          var opts = [{ value: "", label: "All clients" }]
          if (root.service) opts = opts.concat(root.service.clientOptions())
          return opts
        }
        onChanged: function(value) {
          root.clientId = value
          root.applyFilters()
        }
      }

      Dropdown {
        id: projectDrop
        label: "Project"
        showLabel: true
        width: Style.space(190)
        value: root.projectId
        options: {
          var opts = [{ value: "", label: "All projects" }]
          if (root.service) opts = opts.concat(root.service.allProjectOptions())
          return opts
        }
        onChanged: function(value) {
          root.projectId = value
          root.applyFilters()
        }
      }

      Dropdown {
        id: billableDrop
        label: "Billable"
        showLabel: true
        width: Style.space(120)
        value: root.billableFilter
        options: [
          { value: "", label: "All" },
          { value: "yes", label: "Billable" },
          { value: "no", label: "Non-billable" }
        ]
        onChanged: function(value) {
          root.billableFilter = value
          root.applyFilters()
        }
      }

      TextField {
        id: searchField
        placeholderText: "Search…"
        width: Style.space(150)
        onTextChanged: {
          root.search = text
          searchDebounce.restart()
        }
      }
    }

    // ---- pager + status -------------------------------------------------------
    Row {
      spacing: Style.space(8)

      Button {
        text: "←"
        focusable: true
        enabled: root.offset > 0
        onClicked: root.prevPage()
      }

      Text {
        text: root.total > 0
          ? "Showing " + (root.offset + 1) + "–" + Math.min(root.offset + root.limit, root.total)
            + " of " + root.total
          : "No entries"
        color: Color.muted
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Button {
        text: "→"
        focusable: true
        enabled: root.offset + root.limit < root.total
        onClicked: root.nextPage()
      }

      Item { width: 1 }

      Text {
        text: root.flash
        color: Color.accent
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
        visible: root.flash !== ""
      }

      Text {
        text: root.service ? root.service.lastError : ""
        color: Color.urgent
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        visible: root.service && root.service.lastError !== ""
      }
    }
  }

  // ---- list ---------------------------------------------------------------------
  ListView {
    id: listView
    anchors {
      left: parent.left
      right: parent.right
      top: topControls.bottom
      topMargin: Style.space(10)
      bottom: totalsBar.top
      bottomMargin: Style.space(10)
    }
    model: root.entries
    spacing: 2
    clip: true
    interactive: false

    delegate: EntryRow {
      width: listView.width
      service: root.service
      onEditRequested: root.openEdit(modelData)
      onDeleteRequested: root.requestDelete(modelData)
    }
  }

  // ---- totals ---------------------------------------------------------------------
  Item {
    id: totalsBar
    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
    }
    height: Style.space(20)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Total " + (root.service ? root.service.fmtHM(root.totalSeconds) : "—")
        + " · billable " + (root.service ? root.service.fmtHM(root.billableSeconds) : "—")
        + " · " + root.total + " entries"
      color: Color.muted
      font.pixelSize: Style.font.caption
    }
  }

  // ---- edit card overlay ------------------------------------------------------------
  // Shared card-on-scrim modal (CardOverlay, also the Timer's manual-entry
  // modal): same visual language and dismissal semantics as the
  // window-level confirm dialog — scrim click or Esc discards (Esc via the
  // view's handleKey, routed by the dashboard's key gate).
  CardOverlay {
    id: editOverlay
    anchors.fill: parent
    visible: root.editEntry !== null
    cardWidth: Style.space(420)
    onScrimClicked: root.closeEdit()

    Text {
      text: "Edit entry"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    EntryForm {
      id: editForm
      service: root.service
      width: parent.width
    }

    Row {
      spacing: Style.space(8)

      Button {
        text: "Save"
        leftAlign: true
        focusable: true
        onClicked: {
          var s = root.service
          if (!s) return
          if (!editForm.valid) {
            s.lastError = "Fill in a valid entry"
            return
          }
          s.updateEntry(root.editEntry.id, {
            date: editForm.dateStr,
            time: editForm.timeStr,
            minutes: editForm.minutes,
            clientId: editForm.clientId,
            projectId: editForm.projectId,
            description: editForm.description,
            billable: editForm.billable
          }, function(resp) {
            if (resp.ok) {
              root.closeEdit()
              root.flash = "Entry saved"
              flashTimer.restart()
              root.refreshCurrentPage()
            } else {
              s.lastError = resp.error || "Update failed"
            }
          })
        }
      }

      Button {
        text: "Delete"
        leftAlign: true
        focusable: true
        onClicked: root.requestDelete(root.editEntry)
      }

      Button {
        text: "Close"
        leftAlign: true
        focusable: true
        onClicked: root.closeEdit()
      }
    }
  }

  Timer {
    id: initialLoad
    interval: 0
    repeat: false
    running: root.service !== null
    onTriggered: root.applyFilters()
  }
}
