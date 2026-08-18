import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// Timer tab: live hero + start/pause, the next-task form (last-used
// pre-selected) and manual entry.
Item {
  id: root

  property var service: null
  property var dashboard: null
  property bool inputActive: taskForm.keyActiveItem !== null || entryForm.keyActiveItem !== null
  property string flash: ""

  function heroTaskName() {
    var s = root.service
    if (!s || !s.running || !s.active) return ""
    var client = s.clientName(s.active.clientId)
    var desc = s.active.description !== "" ? s.active.description : ""
    if (desc !== "" && client !== "") return client + " — " + desc
    return desc !== "" ? desc : (client !== "" ? client : "-")
  }

  Timer {
    id: flashTimer
    interval: 2000
    onTriggered: root.flash = ""
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(12)
    clip: true

    // ---- hero ---------------------------------------------------------------
    Item {
      width: parent.width
      height: Style.space(96)

      Column {
        anchors.fill: parent
        spacing: Style.space(4)

        Text {
          text: root.service && root.service.running ? root.service.elapsedLabel : "—"
          color: root.service && root.service.running ? Color.foreground : Qt.darker(Color.foreground, 1.6)
          font.pixelSize: Style.font.displayLarge
          font.bold: true
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
          text: root.service && root.service.running ? root.heroTaskName() : "No active timer"
          color: Color.foreground
          font.pixelSize: Style.font.subtitle
          font.bold: true
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
          text: {
            var s = root.service
            if (!s) return ""
            if (s.running && s.active) {
              var bits = []
              if (s.active.description !== "") bits.push(s.active.description)
              bits.push("started " + s.localTimeStr(s.active.start))
              bits.push(s.active.billable ? "billable" : "non-billable")
              return bits.join(" · ")
            }
            return "Today " + s.fmtHM(s.daySeconds) + " · billable " + s.fmtHM(s.dayBillableSeconds)
          }
          color: Color.muted
          font.pixelSize: Style.font.caption
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }

    Button {
      id: mainButton
      text: root.service && root.service.running ? "Pause" : "Start"
      fontSize: Style.font.subtitle
      leftAlign: true
      focusable: true
      anchors.horizontalCenter: parent.horizontalCenter
      onClicked: {
        var s = root.service
        if (!s) return
        if (s.running) {
          s.stopTask()
        } else {
          if (taskForm.clientId === "" || taskForm.projectId === "") {
            s.lastError = "Pick a client and a project first"
            return
          }
          s.startTask(taskForm.clientId, taskForm.projectId, taskForm.description, taskForm.billable)
        }
      }
    }

    PanelSeparator {}

    PanelSectionHeader {
      text: "Next task"
      width: parent.width
    }

    TaskForm {
      id: taskForm
      service: root.service
      width: parent.width

      Component.onCompleted: {
        if (root.service) taskForm.applyDefaults()
      }
    }

    PanelSeparator {}

    PanelSectionHeader {
      text: "Manual entry"
      width: parent.width
    }

    EntryForm {
      id: entryForm
      service: root.service
      width: parent.width

      Component.onCompleted: {
        if (root.service) entryForm.defaultsToToday()
      }
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
              root.flash = "Entry added"
              flashTimer.restart()
            }
          })
        }
      }

      Text {
        text: root.flash
        color: Color.accent
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
        visible: root.flash !== ""
      }
    }

    Text {
      text: root.service ? root.service.lastError : ""
      color: Color.urgent
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
      visible: root.service && root.service.lastError !== ""
    }

    Item { width: 1; height: 1 }
  }
}
