import QtQuick
import qs.Commons
import qs.Ui

// Projects tab: one section per client. Rename inline, add per client,
// delete with confirmation. The helper blocks deleting a project that
// entries still reference.
Item {
  id: root

  property var service: null
  property var dashboard: null
  property bool dialogOpen: deleteConfirm.opened
  property string deleteProjectId: ""
  property int focusCount: 0
  readonly property bool inputActive: focusCount > 0 || root.dialogOpen

  function projectsFor(clientId) {
    var out = []
    if (root.service) {
      var ps = root.service.projects
      for (var i = 0; i < ps.length; i++)
        if (ps[i].clientId === clientId) out.push(ps[i])
    }
    return out
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
      width: ListView.view.width
      spacing: Style.space(6)

      Text {
        text: modelData.name
        color: Color.foreground
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Repeater {
        model: root.projectsFor(clientSection.modelData.id)

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
            text: clientSection.modelData.name
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
              root.deleteProjectId = modelData.id
              deleteConfirm.opened = true
            }
          }
        }
      }

      Row {
        width: clientSection.width
        spacing: Style.space(8)

        TextField {
          id: addField
          placeholderText: "New project for " + clientSection.modelData.name + "…"
          width: clientSection.width - Style.space(100)
          onActiveFocusChanged: root.focusCount = Math.max(0, root.focusCount + (activeFocus ? 1 : -1))
          onAccepted: addProject()
        }

        Button {
          text: "Add"
          leftAlign: true
          focusable: true
          onClicked: addProject()
        }

        function addProject() {
          var name = addField.text.trim()
          if (!name || !root.service) return
          root.service.addProject(clientSection.modelData.id, name, function(resp) {
            if (resp.ok)
              addField.text = ""
            else
              root.service.lastError = resp.error || "Add failed"
          })
        }
      }
    }
  }

  ConfirmDialog {
    id: deleteConfirm
    message: "Delete this project? Entries that reference it must already be gone."
    onConfirmed: {
      if (root.service && root.deleteProjectId !== "") {
        var id = root.deleteProjectId
        root.service.deleteProject(id, function(resp) {
          if (!resp.ok)
            root.service.lastError = resp.error || "Delete failed"
        })
      }
    }
  }
}
