import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// Timer tab: live hero + start/pause/resume/stop, the next-task form
// (last-used pre-selected, description required) and manual entry.
Item {
  id: root

  property var dashboard: null
  // Bound, not assigned: the panel loader injects the dashboard's service
  // after this view may already be loaded, so a one-shot assignment could
  // stay null forever.
  readonly property var service: root.dashboard ? root.dashboard.service : null
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
          color: {
            var s = root.service
            if (!s || !s.running) return Qt.darker(Color.foreground, 1.6)
            return s.paused ? Qt.darker(Color.foreground, 1.2) : Color.foreground
          }
          font.pixelSize: Style.font.displayLarge
          font.bold: true
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
          text: {
            var s = root.service
            if (!s || !s.running) return "No active timer"
            var name = root.heroTaskName()
            return s.paused ? name + "  (Paused)" : name
          }
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
              if (s.paused) bits.push("paused")
              if (s.active.description !== "") bits.push(s.active.description)
              bits.push("started " + s.localTimeStr(new Date(s.active.start)))
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

    // ---- primary action ---------------------------------------------------
    // Idle: Start (gated by form validity). Running: Pause + Stop.
    // Paused: Resume + Stop.
    Row {
      spacing: Style.space(8)
      anchors.horizontalCenter: parent.horizontalCenter
      visible: !(root.service && root.service.running)

      Button {
        text: "Start"
        fontSize: Style.font.subtitle
        leftAlign: true
        focusable: true
        active: taskForm.valid
        onClicked: {
          var s = root.service
          if (!s) return
          if (taskForm.clientId === "" || taskForm.projectId === "") {
            s.lastError = "Pick a client and a project first"
            return
          }
          if (taskForm.description.trim() === "") {
            s.lastError = "Add a task description first"
            return
          }
          s.startTask(taskForm.clientId, taskForm.projectId, taskForm.description, taskForm.billable)
        }
      }
    }

    Row {
      spacing: Style.space(8)
      anchors.horizontalCenter: parent.horizontalCenter
      visible: !!(root.service && root.service.running)

      Button {
        text: (root.service && root.service.paused) ? "Resume" : "Pause"
        fontSize: Style.font.subtitle
        leftAlign: true
        focusable: true
        active: true
        onClicked: root.service.paused ? root.service.resumeTask() : root.service.pauseTask()
      }

      Button {
        text: "Stop"
        fontSize: Style.font.subtitle
        leftAlign: true
        focusable: true
        active: true
        bordered: true
        onClicked: root.service.stopTask()
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
