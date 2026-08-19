import QtQuick
import qs.Commons
import qs.Ui
import "../components"
// Projects tab: a paginated table (each row a ProjectRow: name + owning
// client, Edit / Del) narrowed by the top Client picker (default
// "All clients"), an add row scoped to the selected client, and a
// centered edit card (CardOverlay) with the same visual language and
// dismissal contract as the Clients edit card. The edit card's client
// picker also moves the project to another client (the update API's
// target client). The helper refuses to delete a project still
// referenced by entries — the error surfaces in the red lastError line
// next to the pager.
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null
  // The window keyCatcher blocks while a picker popup, an add/edit field,
  // or the open edit card owns the keyboard.
  readonly property bool inputActive: clientDrop.popupOpen || editClientDrop.popupOpen
    || focusCount > 0 || root.editProject !== null
  property int focusCount: 0
  property int offset: 0
  readonly property int limit: root.service ? root.service.pageSize : 15
  property var editProject: null
  property string flash: ""

  // The top Client picker: "" (the default, "All clients") shows every
  // project; a concrete client id narrows the table to that client's
  // projects and scopes the add row to it (the helper demands an
  // existing client anyway).
  property string clientFilter: ""

  // The filtered table list; the binding follows the service's projects
  // array, so state changes (add/update/delete) refresh it.
  readonly property var filteredProjects: {
    var s = root.service
    if (!s) return []
    if (root.clientFilter === "") return s.projects
    var out = []
    var ps = s.projects
    for (var i = 0; i < ps.length; i++)
      if (ps[i].clientId === root.clientFilter) out.push(ps[i])
    return out
  }

  readonly property int totalCount: root.filteredProjects.length

  // The edit card's client, set by openEdit(); "" while the card is closed.
  property string editClientId: ""

  Timer {
    id: flashTimer
    interval: 2000
    onTriggered: root.flash = ""
  }

  function addProject() {
    var s = root.service
    var name = addName.text.trim()
    if (!name || !s) return
    if (root.clientFilter === "") {
      s.lastError = "Pick a client first"
      return
    }
    s.addProject(root.clientFilter, name, function(resp) {
      if (resp.ok) {
        addName.text = ""
        // The helper appends, so the new project is on the last page.
        root.offset = Math.max(0, root.totalCount - root.limit)
        root.flash = "Project added"
        flashTimer.restart()
      } else
        s.lastError = resp.error || "Add failed"
    })
  }

  function prevPage() { root.offset = Math.max(0, root.offset - root.limit) }
  function nextPage() {
    root.offset = Math.min(Math.max(0, root.totalCount - root.limit), root.offset + root.limit)
  }

  function openEdit(project) {
    root.editProject = project
    editName.text = project.name
    root.editClientId = project.clientId
  }

  function closeEdit() { root.editProject = null }

  function saveEdit() {
    var s = root.service
    if (!s || root.editProject === null) return
    var name = editName.text.trim()
    if (!name) {
      s.lastError = "Name must not be empty"
      return
    }
    if (root.editClientId === "") {
      s.lastError = "Pick a client"
      return
    }
    if (name === root.editProject.name && root.editClientId === root.editProject.clientId) {
      root.closeEdit()
      return
    }
    var id = root.editProject.id
    s.updateProject(id, name, root.editClientId, function(resp) {
      if (resp.ok) {
        root.closeEdit()
        root.flash = "Project saved"
        flashTimer.restart()
      } else
        s.lastError = resp.error || "Update failed"
    })
  }

  function requestDelete(project) {
    if (!project || !root.dashboard) return
    var id = project.id
    root.dashboard.confirmAction("Delete this project? Entries that reference it must already be gone.", function() {
      if (!root.service) return
      root.service.deleteProject(id, function(resp) {
        if (!resp.ok)
          root.service.lastError = resp.error || "Delete failed"
      })
    })
  }

  // Window-level key gate: the dashboard forwards keys to views that define
  // handleKey. Esc closes the edit card (same dismissal as clicking its
  // scrim).
  function handleKey(event) {
    if (root.editProject !== null && event.key === Qt.Key_Esc) {
      root.closeEdit()
      return true
    }
    return false
  }

  Column {
    id: head
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
      topMargin: Style.space(16)
      leftMargin: Style.space(16)
      rightMargin: Style.space(16)
    }
    spacing: Style.space(10)

    Text {
      text: "Projects"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    // Add row: the Client picker is the table filter (default
    // "All clients") and the add's target — adding while "All clients"
    // is selected surfaces "Pick a client first" in the status line.
    // The name label mirrors the picker label (caption/bold + labelGap)
    // and the field box uses controlHeight, so the boxes line up; the
    // Add button pins to the far right, bottom-aligned with the row.
    Item {
      id: addBar
      width: parent.width
      height: clientDrop.implicitHeight

      Dropdown {
        id: clientDrop
        anchors { left: parent.left; top: parent.top }
        label: "Client"
        showLabel: true
        width: Style.space(170)
        value: root.clientFilter
        options: {
          var opts = [{ value: "", label: "All clients" }]
          if (root.service) opts = opts.concat(root.service.clientOptions())
          return opts
        }
        onChanged: function(value) {
          root.clientFilter = value
          root.offset = 0
        }
      }

      Column {
        id: nameColumn
        spacing: Style.spacing.labelGap
        anchors { right: addBtn.left; rightMargin: Style.space(8); bottom: parent.bottom }

        Text {
          text: "Project"
          color: Qt.darker(Color.popups.text, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          id: addName
          placeholderText: "New project…"
          width: Style.space(220)
          height: Style.spacing.controlHeight
          onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
          onAccepted: root.addProject()
        }
      }

      Button {
        id: addBtn
        text: "Add"
        leftAlign: true
        anchors { right: parent.right; bottom: parent.bottom }
        focusable: true
        onClicked: root.addProject()
      }
    }
  }

  // QML-side pagination: the full projects array stays in the service (the
  // dropdowns need it), only the current page slice of the filtered list
  // becomes the list model.
  ListView {
    id: listView
    anchors {
      left: parent.left
      right: parent.right
      top: head.bottom
      topMargin: Style.space(10)
      bottom: pagerBar.top
      bottomMargin: Style.space(10)
      leftMargin: Style.space(16)
      rightMargin: Style.space(16)
    }
    model: root.filteredProjects.slice(root.offset, root.offset + root.limit)
    spacing: 2
    clip: true

    delegate: ProjectRow {
      width: listView.width
      service: root.service
      onEditRequested: root.openEdit(modelData)
      onDeleteRequested: root.requestDelete(modelData)
    }
  }

  // ---- pager + status ---------------------------------------------------
  // Pinned to the bottom of the table: the shared PaginationBar (page
  // navigation) with the flash/error status texts to its right.
  Row {
    id: pagerBar
    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
      leftMargin: Style.space(16)
      rightMargin: Style.space(16)
      bottomMargin: Style.space(16)
    }
    spacing: Style.space(8)

    PaginationBar {
      id: pageBar
      total: root.totalCount
      offset: root.offset
      limit: root.limit
      emptyText: "No projects"
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

  // ---- edit card overlay --------------------------------------------------
  // Shared card-on-scrim modal (CardOverlay): same visual language and
  // dismissal semantics as the Clients edit card — scrim click or Esc
  // discards (Esc via the view's handleKey, routed by the dashboard's key
  // gate). Enter in the name field saves. Changing the client picker moves
  // the project; uniqueness is checked against the target client.
  CardOverlay {
    id: editOverlay
    anchors.fill: parent
    visible: root.editProject !== null
    cardWidth: Style.space(420)
    onScrimClicked: root.closeEdit()

    Text {
      text: "Edit project"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    TextField {
      id: editName
      width: parent.width
      placeholderText: "Project name"
      onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
      onAccepted: root.saveEdit()
    }

    Dropdown {
      id: editClientDrop
      label: "Client"
      showLabel: true
      width: parent.width
      value: root.editClientId
      options: root.service ? root.service.clientOptions() : []
      onChanged: function(value) { root.editClientId = value }
    }

    Row {
      spacing: Style.space(8)

      Button {
        text: "Save"
        leftAlign: true
        focusable: true
        onClicked: root.saveEdit()
      }

      Button {
        text: "Close"
        leftAlign: true
        focusable: true
        onClicked: root.closeEdit()
      }
    }
  }
}
