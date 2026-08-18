import QtQuick
import qs.Commons
import qs.Ui

// Projects tab: one section per client. Rename inline, add per client,
// delete with confirmation. The helper blocks deleting a project that
// entries still reference.
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
    var out = []
    if (root.service) {
      var ps = root.service.projects
      for (var i = 0; i < ps.length; i++)
        if (ps[i].clientId === clientId) out.push(ps[i])
    }
    return out
  }

  function addProject(clientId, name, done) {
    if (!name || !root.service) return
    root.service.addProject(clientId, name, function(resp) {
      if (!resp.ok)
        root.service.lastError = resp.error || "Add failed"
      if (done) done(resp)
    })
  }

  ListView {
    id: listView
    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      bottom: parent.bottom
    }
    model: root.service ? root.service.clients : []
    spacing: Style.space(14)
    clip: true

    delegate: Column {
      id: clientSection
      property var client: modelData
      width: ListView.view.width
      spacing: Style.space(6)

      Text {
        text: clientSection.client.name
        color: Color.foreground
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Row {
        width: clientSection.width
        spacing: Style.space(8)

        TextField {
          id: addField
          placeholderText: "New project for " + clientSection.client.name + "…"
          width: clientSection.width - Style.space(100)
          onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
          onAccepted: root.addProject(clientSection.client.id, addField.text.trim(), function(resp) { if (resp.ok) addField.text = "" })
        }

        Button {
          text: "Add"
          leftAlign: true
          focusable: true
          onClicked: root.addProject(clientSection.client.id, addField.text.trim(), function(resp) { if (resp.ok) addField.text = "" })
        }
      }

      Repeater {
        model: root.projectsFor(clientSection.client.id)

        delegate: Row {
          width: clientSection.width
          spacing: Style.space(8)

          TextField {
            text: modelData.name
            width: parent.width - Style.space(180)
            onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
            onAccepted: {
              var name = text.trim()
              if (name && name !== modelData.name)
                root.service.updateProject(modelData.id, name, modelData.clientId, function(resp) {
                  if (!resp.ok)
                    root.service.lastError = resp.error || "Rename failed"
                })
            }
          }

          Text {
            text: clientSection.client.name
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
              root.dashboard.confirmAction("Delete this project? Entries that reference it must already be gone.", function() {
                if (!root.service) return
                root.service.deleteProject(id, function(resp) {
                  if (!resp.ok)
                    root.service.lastError = resp.error || "Delete failed"
                })
              })
            }
          }
        }
      }
    }
  }
}
