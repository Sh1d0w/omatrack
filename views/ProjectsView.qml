import QtQuick
import qs.Commons
import qs.Ui
import "../components"
// Projects tab: a paginated table (each row a ProjectRow: name + owning
// client, Edit / Del) narrowed by the top Client picker (default
// "All clients"), an Add project button opening a centered add card with
// its own Client picker, and a centered edit card — both CardOverlay
// modals with the same visual language and dismissal contract as the
// Clients edit card. The edit card's client picker also moves the
// project to another client (the update API's target client). The helper
// refuses to delete a project still referenced by entries — the error
// surfaces in the red lastError line next to the pager.
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null
  // The window keyCatcher blocks while a picker popup, an add/edit field,
  // or an open add/edit card owns the keyboard.
  readonly property bool inputActive: clientDrop.popupOpen || addClientDrop.popupOpen
    || editClientDrop.popupOpen || focusCount > 0
    || root.editProject !== null || root.addProjectOpen
  property int focusCount: 0
  property int offset: 0
  readonly property int limit: root.service ? root.service.pageSize : 15
  property var editProject: null
  property bool addProjectOpen: false
  // The add card's client; "" until the card is first opened.
  property string addClientId: ""
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

  readonly property string emptyMessage:
    root.clientFilter === "" ? "No projects" : "No projects for this client"

  // The edit card's client, set by openEdit(); "" while the card is closed.
  property string editClientId: ""

  Timer {
    id: flashTimer
    interval: 2000
    onTriggered: root.flash = ""
  }

  function openAdd() {
    var s = root.service
    if (!s) return
    addName.text = ""
    // Default to the table's filtered client when one is picked, else the
    // first client.
    root.addClientId = (root.clientFilter !== "" && s.clientName(root.clientFilter) !== "")
      ? root.clientFilter
      : (s.clients.length > 0 ? s.clients[0].id : "")
    // Explicit set: a previous in-card picker selection replaces the
    // value binding, which would otherwise leave a stale label here.
    addClientDrop.value = root.addClientId
    root.addProjectOpen = true
    Qt.callLater(function() { addName.forceActiveFocus() })
  }

  function closeAdd() { root.addProjectOpen = false }

  function addProject() {
    var s = root.service
    var name = addName.text.trim()
    if (!name || !s) return
    if (root.addClientId === "") {
      s.lastError = "Pick a client"
      return
    }
    s.addProject(root.addClientId, name, function(resp) {
      if (resp.ok) {
        root.closeAdd()
        // The new project belongs to the add card's client: follow it in
        // the filter so the new row is visible (the helper appends, so it
        // is on the last page).
        root.clientFilter = root.addClientId
        clientDrop.value = root.addClientId
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
    // Explicit set: a previous in-card picker selection replaces the
    // value binding, which would otherwise leave a stale label here.
    editClientDrop.value = project.clientId
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
  // handleKey. Esc closes whichever card is open (the add card is declared
  // last, so it wins), same dismissal as clicking its scrim.
  function handleKey(event) {
    if (root.addProjectOpen && event.key === Qt.Key_Esc) {
      root.closeAdd()
      return true
    }
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

    // Top row: the Client picker is the table filter (default "All
    // clients"); the Add button pins to the far right and opens the add
    // card (CardOverlay) with its own Client picker, which defaults to
    // the filtered client.
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

      Button {
        id: addBtn
        text: "Add project"
        leftAlign: true
        anchors { right: parent.right; bottom: parent.bottom }
        focusable: true
        onClicked: root.openAdd()
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

    EmptyMessage {
      message: root.emptyMessage
      visible: root.totalCount === 0
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
      emptyText: root.emptyMessage
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

  // ---- add card overlay --------------------------------------------------
  // Same CardOverlay language and dismissal as the edit card: a name
  // field (focused on open) and a Client picker (defaulting to the
  // filtered client, else the first). **Add project** or Enter commits
  // (name non-empty, client picked); scrim click or Esc discards.
  // Declared after the edit card, so it draws above it and wins the Esc
  // gate. A successful add filters the table to the picked client and
  // jumps to the last page.
  CardOverlay {
    id: addOverlay
    anchors.fill: parent
    visible: root.addProjectOpen
    cardWidth: Style.space(420)
    onScrimClicked: root.closeAdd()

    Text {
      text: "Add project"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    TextField {
      id: addName
      width: parent.width
      placeholderText: "Project name"
      onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
      onAccepted: root.addProject()
    }

    Dropdown {
      id: addClientDrop
      label: "Client"
      showLabel: true
      width: parent.width
      value: root.addClientId
      options: root.service ? root.service.clientOptions() : []
      onChanged: function(value) { root.addClientId = value }
    }

    Row {
      spacing: Style.space(8)

      Button {
        text: "Add project"
        leftAlign: true
        focusable: true
        onClicked: root.addProject()
      }

      Button {
        text: "Close"
        leftAlign: true
        focusable: true
        onClicked: root.closeAdd()
      }
    }
  }
}
