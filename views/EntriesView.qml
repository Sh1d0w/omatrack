import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// Entries tab: date presets + filters, a paginated entry list (fixed page
// size — the full array never enters QML), manual entry add, and
// edit/delete, all through centered card overlays.
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null
  property string flash: ""

  // The window keyCatcher blocks while a filter control, a form field, or
  // a card overlay owns the keyboard.
  readonly property bool inputActive: clientDrop.popupOpen || projectDrop.popupOpen
    || billableDrop.popupOpen || searchField.activeFocus || rangeBar.fieldActive
    || editForm.keyActiveItem !== null || root.editEntry !== null
    || entryForm.keyActiveItem !== null || root.entryModalOpen

  // ---- state -----------------------------------------------------------------
  property var entries: []
  property int total: 0
  property int totalSeconds: 0
  property int billableSeconds: 0
  property int offset: 0
  readonly property int limit: root.service ? root.service.pageSize : 15

  property string from: ""
  property string to: ""
  property string clientId: ""
  property string projectId: ""
  property string billableFilter: ""   // "" | "yes" | "no"
  property string search: ""
  property string currentPreset: "all"
  property var editEntry: null
  property bool entryModalOpen: false

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

  function closeEntryModal() { root.entryModalOpen = false }

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
  // handleKey. Esc closes whichever card overlay is open (the most recently
  // opened one wins — same dismissal as clicking its scrim).
  function handleKey(event) {
    if (root.entryModalOpen && event.key === Qt.Key_Esc) {
      root.closeEntryModal()
      return true
    }
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

    // ---- filter row + manual-entry action ----------------------------------
    // "Add manual entry" pins to the row's far right, bottom-aligned with
    // the dropdown input fields (shared bottom edge). Anchored, not a
    // stretch spacer, so it holds its position at any window width.
    Item {
      id: filterBar
      width: parent.width
      height: filterRow.implicitHeight

      Row {
        id: filterRow
        anchors { left: parent.left; top: parent.top }
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

      Button {
        id: addEntryButton
        text: "Add manual entry"
        anchors { right: parent.right; bottom: parent.bottom }
        focusable: true
        onClicked: root.entryModalOpen = true
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
      bottom: pagerBar.top
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

  // ---- pager + status -----------------------------------------------------------
  // Pinned to the bottom of the table: the shared PaginationBar (page
  // navigation) with the flash/error status texts to its right.
  Row {
    id: pagerBar
    anchors {
      left: parent.left
      right: parent.right
      bottom: totalsBar.top
      bottomMargin: Style.space(10)
    }
    spacing: Style.space(8)

    PaginationBar {
      id: pageBar
      total: root.total
      offset: root.offset
      limit: root.limit
      emptyText: "No entries"
      onPrevRequested: root.prevPage()
      onNextRequested: root.nextPage()
    }

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

  // ---- edit card overlay --------------------------------------------------------
  // Shared card-on-scrim modal (CardOverlay, also the manual-entry modal
  // below): same visual language and dismissal semantics as the
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

  // ---- manual-entry card overlay -------------------------------------------------
  // Same shared CardOverlay language as the edit card. The EntryForm fills
  // today's date/time and the last-used task defaults on service injection;
  // a successful add re-queries the current page.
  CardOverlay {
    id: entryOverlay
    anchors.fill: parent
    visible: root.entryModalOpen
    cardWidth: Style.space(420)
    onScrimClicked: root.closeEntryModal()

    Text {
      text: "Add manual entry"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    EntryForm {
      id: entryForm
      service: root.service
      width: parent.width
    }

    Row {
      spacing: Style.space(8)

      Button {
        text: "Add entry"
        leftAlign: true
        focusable: true
        onClicked: {
          var s = root.service
          if (!s) return
          if (!entryForm.valid) {
            s.lastError = "Fill in a valid manual entry"
            return
          }
          s.addEntry({
            date: entryForm.dateStr,
            time: entryForm.timeStr,
            minutes: entryForm.minutes,
            clientId: entryForm.clientId,
            projectId: entryForm.projectId,
            description: entryForm.description,
            billable: entryForm.billable
          }, function(resp) {
            if (resp.ok) {
              root.closeEntryModal()
              root.flash = "Entry added"
              flashTimer.restart()
              root.refreshCurrentPage()
            } else {
              s.lastError = resp.error || "Add failed"
            }
          })
        }
      }

      Button {
        text: "Close"
        leftAlign: true
        focusable: true
        onClicked: root.closeEntryModal()
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
