import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"

// Quick-start popup anchored to the bar widget: live status, start/pause,
// the new-task form (last client + project pre-selected by default) and a
// shortcut to the dashboard.
//
// Shape contract for the bar (Bar.findPanelWidget): `opened`/`open()`/
// `close()`/`toggle()` come from the Panel base; `popoutSwitchClosing` and
// `closeForPopoutSwitch()` mirror the KeyboardPanel's popout coordination.
// The BarWidget forwards those calls here, so the bar can treat this popup
// as its popout identity.
Panel {
  id: root
  moduleName: "io.github.sh1d0w.timetrack"
  manageIpc: false  // the service owns the single "timetrack" IPC target

  // Injected by the BarWidget via injectPopup().
  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  // Form state: TaskForm owns the four values (it persists while this popup
  // is alive, so a half-filled form survives a stray Esc). applyDefaults()
  // seeds last-used values until the user edits anything.
  readonly property bool formReady: taskForm.clientId !== "" && taskForm.projectId !== ""

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
            ? Color.accent
            : Qt.darker(Color.foreground, 1.8)
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: parent.width - Style.space(18)
          spacing: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter

          Text {
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
            width: parent.width
            elide: Text.ElideRight
            text: {
              var s = root.service
              if (!s) return ""
              if (s.running && s.active)
                return s.elapsedLabel + " · " + (s.active.billable ? "billable" : "non-billable")
              return s.daySeconds > 0 ? "Today " + s.fmtHM(s.daySeconds) : "Start a task below"
            }
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
        }
      }

      // 2. Primary action --------------------------------------------------
      Button {
        width: parent.width
        fontSize: Style.font.subtitle
        text: root.service && root.service.running ? "Pause" : "Start"
        focusable: true
        active: !!(root.service && !root.service.running) && root.formReady
        onClicked: {
          if (root.service && root.service.running) root.service.stopTask()
          else root.startFromForm()
        }
      }

      PanelSeparator {}

      PanelSectionHeader {
        text: "New task"
      }

      // 3. New-task form ----------------------------------------------------
      TaskForm {
        id: taskForm
        width: parent.width
        service: root.service
      }

      PanelSeparator {}

      // 4. Footer -----------------------------------------------------------
      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: root.service ? "Today " + root.service.fmtHM(root.service.daySeconds) : ""
          color: Color.muted
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Item { width: 1 }

        Button {
          text: "Dashboard…"
          leftAlign: true
          focusable: true
          onClicked: root.openDashboard()
        }
      }

      // 5. Errors -----------------------------------------------------------
      Text {
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

  onOpenedChanged: { if (opened) Qt.callLater(function() { taskForm.applyDefaults() }) }
  onServiceChanged: { taskForm.applyDefaults() }
  Component.onCompleted: { taskForm.applyDefaults() }

  // ---- actions ---------------------------------------------------------------

  function startFromForm() {
    if (!root.service || root.service.running) return
    if (taskForm.clientId === "" || taskForm.projectId === "") {
      root.service.lastError = "Pick a client and project"
      return
    }
    root.service.startTask(taskForm.clientId, taskForm.projectId, taskForm.description, taskForm.billable)
  }

  function openDashboard() {
    var sh = root.bar ? root.bar.shell : null
    if (sh && typeof sh.summon === "function") {
      sh.summon("io.github.sh1d0w.timetrack", JSON.stringify({}))
    }
  }
}
