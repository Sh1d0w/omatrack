import QtQuick
import qs.Commons
import qs.Ui
import "../components"
// Clients tab: rename inline (Enter commits), add (new clients append at
// the end and the list jumps to them), delete with confirmation, and a
// bottom pager. The helper refuses to delete a client still referenced
// by projects or entries — the error surfaces in lastError.
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null
  property int focusCount: 0
  readonly property bool inputActive: focusCount > 0
  property int offset: 0
  readonly property int limit: root.service ? root.service.pageSize : 15

  function projectsFor(clientId) {
    var n = 0
    if (root.service) {
      var ps = root.service.projects
      for (var i = 0; i < ps.length; i++)
        if (ps[i].clientId === clientId) n++
    }
    return n
  }

  function addClient() {
    var name = addName.text.trim()
    if (!name || !root.service) return
    root.service.addClient(name, function(resp) {
      if (resp.ok) {
        addName.text = ""
        // The helper appends, so the new client is on the last page.
        root.offset = Math.max(0, root.totalCount - root.limit)
      } else
        root.service.lastError = resp.error || "Add failed"
    })
  }

  Column {
    id: head
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    spacing: Style.space(10)

    Text {
      text: "Clients"
      color: Color.foreground
      font.pixelSize: Style.font.title
      font.bold: true
    }

    // Add row: the button pins to the far right, bottom-aligned with the
    // input (shared bottom edge); anchored, not a stretch spacer, so it
    // holds its position at any window width.
    Item {
      id: addBar
      width: parent.width
      height: addName.implicitHeight

      TextField {
        id: addName
        anchors { left: parent.left; top: parent.top }
        placeholderText: "New client…"
        width: Style.space(220)
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onAccepted: root.addClient()
      }

      Button {
        text: "Add"
        leftAlign: true
        anchors { right: parent.right; bottom: parent.bottom }
        focusable: true
        onClicked: root.addClient()
      }
    }
  }

  // QML-side pagination: the full clients array stays in the service (the
  // dropdowns need it), only the current page slice becomes the list model.
  readonly property int totalCount: root.service ? root.service.clients.length : 0

  function prevPage() { root.offset = Math.max(0, root.offset - root.limit) }
  function nextPage() {
    root.offset = Math.min(Math.max(0, root.totalCount - root.limit), root.offset + root.limit)
  }

  ListView {
    id: listView
    anchors {
      left: parent.left
      right: parent.right
      top: head.bottom
      topMargin: Style.space(10)
      bottom: pageBar.top
      bottomMargin: Style.space(10)
    }
    model: root.service ? root.service.clients.slice(root.offset, root.offset + root.limit) : []
    spacing: 2
    clip: true

    delegate: Row {
      id: clientRow
      width: ListView.view.width
      spacing: Style.space(8)

      TextField {
        text: modelData.name
        width: parent.width - Style.space(230)
        font.bold: true
        font.pixelSize: Style.font.body
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onAccepted: {
          var name = text.trim()
          if (name && name !== modelData.name)
            root.service.updateClient(modelData.id, name, function(resp) {
              if (!resp.ok)
                root.service.lastError = resp.error || "Rename failed"
            })
        }
      }

      Text {
        text: root.projectsFor(modelData.id) + " projects"
          + (modelData.createdAt ? " · added " + root.service.localDateStr(new Date(modelData.createdAt)) : "")
        color: Color.muted
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Button {
        text: "Del"
        leftAlign: true
        focusable: true
        anchors.verticalCenter: parent.verticalCenter
        onClicked: {
          var id = modelData.id
          root.dashboard.confirmAction("Delete this client? Its projects and entries must already be gone.", function() {
            if (!root.service) return
            root.service.deleteClient(id, function(resp) {
              if (!resp.ok)
                root.service.lastError = resp.error || "Delete failed"
            })
          })
        }
      }
    }
  }

  // ---- pager --------------------------------------------------------------------
  PaginationBar {
    id: pageBar
    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
    }
    total: root.totalCount
    offset: root.offset
    limit: root.limit
    emptyText: "No clients"
    onPrevRequested: root.prevPage()
    onNextRequested: root.nextPage()
  }
}
