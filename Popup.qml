import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"

// Quick-start popup anchored to the bar widget: live status, the new-task
// form (client/project/description, last-used values pre-selected by
// default) with Start below it, pause/resume/stop, and a ⚙ icon button at
// the top right that opens the dashboard.
//
// The new-task section (header, form, Start) is idle-only: while a task
// runs — paused included — the popup shrinks to status + controls and
// returns to the full layout when the task stops.
//
// Shape contract for the bar (Bar.findPanelWidget): `opened`/`open()`/
// `close()`/`toggle()` come from the Panel base; `popoutSwitchClosing` and
// `closeForPopoutSwitch()` mirror the KeyboardPanel's popout coordination.
// The BarWidget forwards those calls here, so the bar can treat this popup
// as its popout identity.
Panel {
  id: root
  moduleName: "io.github.sh1d0w.omatrack"
  manageIpc: false  // the service owns the single "omatrack" IPC target

  // Injected by the BarWidget via injectPopup().
  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  // Form state: TaskForm owns the four values (it persists while this popup
  // is alive, so a half-filled form survives a stray Esc). applyDefaults()
  // seeds last-used values until the user edits anything.
  readonly property bool formReady: taskForm.valid

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.hostWidget || root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // A form control owns the keys while one of them is focused or its
      // dropdown is open; Esc/Enter are handled by that control then.
      blocked: taskForm.keyActiveItem !== null
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onReturnRequested: {
        if (!taskForm.keyActiveItem && root.service && !root.service.running)
          root.startFromForm()
      }
      onActivateRequested: {
        if (!taskForm.keyActiveItem && root.service && !root.service.running)
          root.startFromForm()
      }
    }

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.space(10)

      // 1. Status row -----------------------------------------------------
      Row {
        width: parent.width
        spacing: Style.space(10)

        Rectangle {
          width: Style.space(8)
          height: Style.space(8)
          radius: width / 2
          color: root.service && root.service.running
            ? (root.service.paused ? Qt.darker(Color.foreground, 1.4) : Color.accent)
            : Qt.darker(Color.foreground, 1.8)
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: parent.width - Style.space(8) - dashboardButton.implicitWidth - 2 * Style.space(10)
          spacing: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: {
              var s = root.service
              if (!s || !s.running || !s.active) return "No active timer"
              var desc = s.active.description !== "" ? s.active.description : null
              var client = s.clientName(s.active.clientId)
              if (desc) return client !== "" ? client + " — " + desc : desc
              return client !== "" ? client : "-"
            }
            color: Color.foreground
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: {
              var s = root.service
              if (!s) return ""
              if (s.running && s.active)
                return s.elapsedLabel + " · "
                  + (s.paused ? "paused · " : "")
                  + (s.active.billable ? "billable" : "non-billable")
              return s.daySeconds > 0 ? "Today " + s.fmtHM(s.daySeconds) : "Start a task below"
            }
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
        }
        PanelActionButton {
          id: dashboardButton
          iconText: "⚙"
          tooltipText: "Open dashboard"
          focusable: true
          size: Style.space(30)
          fontSize: Style.font.iconLarge
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.openDashboard()
        }
      }

      // 2. New-task section ---------------------------------------------------
      // Header + form + Start are idle-only: while a task runs (paused
      // included) there is no next task to line up; all of it returns when
      // the task stops.
      PanelSectionHeader {
        text: "New task"
        visible: !(root.service && root.service.running)
      }

      TaskForm {
        id: taskForm
        width: parent.width
        service: root.service
        visible: !(root.service && root.service.running)
      }

      Button {
        id: startButton
        width: parent.width
        fontSize: Style.font.subtitle
        text: "Start"
        visible: !(root.service && root.service.running)
        focusable: true
        active: root.formReady
        onClicked: root.startFromForm()
      }

      // 3. Primary action ----------------------------------------------------
      // Running: Pause + Stop. Paused: Resume + Stop. (The old single
      // "Pause" button actually *stopped* the task; its mislabel is gone.)
      Row {
        width: parent.width
        spacing: Style.space(8)
        visible: !!(root.service && root.service.running)

        Button {
          id: pauseResumeButton
          width: parent.width - stopButton.implicitWidth - parent.spacing
          fontSize: Style.font.subtitle
          text: root.service && root.service.paused ? "Resume" : "Pause"
          focusable: true
          active: true
          onClicked: root.service && root.service.paused ? root.service.resumeTask() : root.service.pauseTask()
        }

        Button {
          id: stopButton
          fontSize: Style.font.subtitle
          text: "Stop"
          focusable: true
          active: true
          bordered: true
          onClicked: root.service.stopTask()
        }
      }

      // 4. Errors -----------------------------------------------------------
      Text {
        textFormat: Text.PlainText
        visible: !!root.service && root.service.lastError !== ""
        text: root.service ? root.service.lastError : ""
        color: Color.urgent
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }
  }

  // ---- lifecycle -----------------------------------------------------------

  // TaskForm self-seeds its last-used defaults when the service is
  // injected (its onServiceChanged); the only thing the popup must do
  // is re-arm the seeding on reopen.
  onOpenedChanged: { if (opened) Qt.callLater(function() { taskForm.applyDefaults() }) }

  // ---- actions ---------------------------------------------------------------

  function startFromForm() {
    if (!root.service || root.service.running) return
    if (taskForm.clientId === "" || taskForm.projectId === "") {
      root.service.lastError = "Pick a client and project"
      return
    }
    if (taskForm.description.trim() === "") {
      root.service.lastError = "Add a task description"
      return
    }
    root.service.startTask(taskForm.clientId, taskForm.projectId, taskForm.description, taskForm.billable)
  }

  function openDashboard() {
    var sh = root.bar ? root.bar.shell : null
    // The summon goes through the shell's panel-loader path, which never
    // touches the bar's popout, so the popup must hide itself or it stays
    // open over the dashboard window.
    root.close()
    if (sh && typeof sh.summon === "function") {
      sh.summon("io.github.sh1d0w.omatrack", JSON.stringify({}))
    }
  }
}
