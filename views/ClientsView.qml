import QtQuick
import qs.Commons
import qs.Ui
import "../components"
// Clients tab: a paginated table (each row a ClientRow: name + meta, Edit
// / Del), a "+" button in the heading row (tooltip "Add client") opening
// a centered add card, and a centered edit card — both CardOverlay modals
// with the same visual language and dismissal contract as the Entries
// edit card. The helper refuses to delete a client still referenced by
// projects or entries — the error surfaces in the red lastError line
// next to the pager.
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null
  property int focusCount: 0
  // The window keyCatcher blocks while the add card or the edit card
  // (its field, or just the open card) owns the keyboard.
  readonly property bool inputActive: focusCount > 0 || root.editClient !== null
    || root.addClientOpen
  property int offset: 0
  readonly property int limit: root.service ? root.service.pageSize : 15
  readonly property int totalCount: root.service ? root.service.clients.length : 0
  property var editClient: null
  property bool addClientOpen: false
  property string flash: ""

  Timer {
    id: flashTimer
    interval: 2000
    onTriggered: root.flash = ""
  }

  function openAdd() {
    if (!root.service) return
    addName.text = ""
    root.addClientOpen = true
    Qt.callLater(function() { addName.forceActiveFocus() })
  }

  function closeAdd() { root.addClientOpen = false }

  function addClient() {
    var name = addName.text.trim()
    if (!name || !root.service) return
    root.service.addClient(name, function(resp) {
      if (resp.ok) {
        root.closeAdd()
        // The helper appends, so the new client is on the last page.
        root.offset = Math.max(0, root.totalCount - root.limit)
        root.flash = "Client added"
        flashTimer.restart()
      } else
        root.service.lastError = resp.error || "Add failed"
    })
  }

  function prevPage() { root.offset = Math.max(0, root.offset - root.limit) }
  function nextPage() {
    root.offset = Math.min(Math.max(0, root.totalCount - root.limit), root.offset + root.limit)
  }

  function openEdit(client) {
    root.editClient = client
    editName.text = client.name
  }

  function closeEdit() { root.editClient = null }

  function saveEdit() {
    var s = root.service
    if (!s || root.editClient === null) return
    var name = editName.text.trim()
    if (!name) {
      s.lastError = "Name must not be empty"
      return
    }
    if (name === root.editClient.name) {
      root.closeEdit()
      return
    }
    var id = root.editClient.id
    s.updateClient(id, name, function(resp) {
      if (resp.ok) {
        root.closeEdit()
        root.flash = "Client saved"
        flashTimer.restart()
      } else
        s.lastError = resp.error || "Rename failed"
    })
  }

  function requestDelete(client) {
    if (!client || !root.dashboard) return
    var id = client.id
    root.dashboard.confirmAction("Delete this client? Its projects and entries must already be gone.", function() {
      if (!root.service) return
      root.service.deleteClient(id, function(resp) {
        if (!resp.ok)
          root.service.lastError = resp.error || "Delete failed"
      })
    })
  }

  // Window-level key gate: the dashboard forwards keys to views that define
  // handleKey. Esc closes whichever card is open (the add card is declared
  // last, so it wins), same dismissal as clicking its scrim.
  function handleKey(event) {
    if (root.addClientOpen && event.key === Qt.Key_Esc) {
      root.closeAdd()
      return true
    }
    if (root.editClient !== null && event.key === Qt.Key_Esc) {
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

    // Heading row: title on the left, the "+" add button on the far
    // right, vertically centered; the tooltip names the action (open the
    // add card).
    Item {
      width: parent.width
      height: Math.max(headTitle.implicitHeight, addButton.implicitHeight)

      Text {
        id: headTitle
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "Clients"
        color: Color.foreground
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Button {
        id: addButton
        iconText: "+"
        tooltipText: "Add client"
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        focusable: true
        onClicked: root.openAdd()
      }
    }

    Text {
      text: "The companies your time is billed to — each row shows its projects and creation date; a client with projects or entries cannot be deleted."
      color: Color.muted
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.Wrap
    }
  }

  // QML-side pagination: the full clients array stays in the service (the
  // dropdowns need it), only the current page slice becomes the list model.
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
    model: root.service ? root.service.clients.slice(root.offset, root.offset + root.limit) : []
    spacing: 2
    clip: true

    delegate: ClientRow {
      width: listView.width
      service: root.service
      onEditRequested: root.openEdit(modelData)
      onDeleteRequested: root.requestDelete(modelData)
    }

    EmptyMessage {
      message: "No clients"
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
      emptyText: "No clients"
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
  // dismissal semantics as the Entries edit card — scrim click or Esc
  // discards (Esc via the view's handleKey, routed by the dashboard's key
  // gate). Enter in the name field saves.
  CardOverlay {
    id: editOverlay
    anchors.fill: parent
    visible: root.editClient !== null
    cardWidth: Style.space(420)
    onScrimClicked: root.closeEdit()

    Text {
      text: "Edit client"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    TextField {
      id: editName
      width: parent.width
      placeholderText: "Client name"
      onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
      onAccepted: root.saveEdit()
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
  // Same CardOverlay language and dismissal as the edit card: a single
  // name field (focused on open); **Add client** or Enter commits
  // (non-empty), scrim click or Esc discards. Declared after the edit
  // card, so it draws above it and wins the Esc gate.
  CardOverlay {
    id: addOverlay
    anchors.fill: parent
    visible: root.addClientOpen
    cardWidth: Style.space(420)
    onScrimClicked: root.closeAdd()

    Text {
      text: "Add client"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    TextField {
      id: addName
      width: parent.width
      placeholderText: "Client name"
      onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
      onAccepted: root.addClient()
    }

    Row {
      spacing: Style.space(8)

      Button {
        text: "Add client"
        leftAlign: true
        focusable: true
        onClicked: root.addClient()
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
