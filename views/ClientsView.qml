import QtQuick
import qs.Commons
import qs.Ui

// Clients tab: rename inline (Enter commits), add at top, delete with
// confirmation. The helper refuses to delete a client still referenced
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
      if (resp.ok)
        addName.text = ""
      else
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

    Row {
      spacing: Style.space(8)

      TextField {
        id: addName
        placeholderText: "New client…"
        width: Style.space(220)
        onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
        onAccepted: root.addClient()
      }

      Button {
        text: "Add"
        leftAlign: true
        focusable: true
        onClicked: root.addClient()
      }
    }
  }

  ListView {
    id: listView
    anchors {
      left: parent.left
      right: parent.right
      top: head.bottom
      topMargin: Style.space(10)
      bottom: parent.bottom
    }
    model: root.service ? root.service.clients : []
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
}
