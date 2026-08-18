import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Dashboard: a real toplevel window managing timer, entries, clients,
// projects, reports, invoices and settings.
//
// Contract with the shell panel loader (dev-gallery shape): `open(payloadJson)`
// shows the window, `close()` hides it without telling the shell, and closing
// from the window side (titlebar X / Esc) routes through `shell.hide(id)` so
// the loader drops the instance. `service` is declared on the root, so the
// host injects the plugin's live Service singleton.
Item {
  id: root

  property bool closingFromHost: false
  property var shell: null
  property var service: null
  property var confirmPending: null

  readonly property string pluginId: "io.github.sh1d0w.timetrack"
  property string activeTab: "timer"

  function open(payloadJson) {
    closingFromHost = false
    closeConfirm()
    window.visible = true
    // Optional {"tab": "<id>"} in the payload opens a specific tab. Unknown
    // ids are ignored — the dashboard opens on the timer tab.
    var requested = ""
    if (payloadJson) {
      try {
        var parsed = JSON.parse(String(payloadJson))
        if (parsed && typeof parsed.tab === "string") requested = parsed.tab
      } catch (e) { /* ignore */ }
    }
    Qt.callLater(function() {
      for (var i = 0; i < tabs.length; i++)
        if (tabs[i].id === requested) root.activeTab = requested
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    else
      window.visible = false
  }

  // Window-level confirmation for destructive actions. The dialog fills the
  // window, so its card centers over the whole window and the scrim covers
  // sidebar and header alike. Views call confirmAction; onConfirm runs after
  // the dialog closes.
  function confirmAction(message, onConfirm) {
    confirmDialog.message = message
    confirmDialog.selectedIndex = 1
    confirmPending = onConfirm
    confirmDialog.opened = true
  }

  function closeConfirm() {
    confirmDialog.opened = false
    confirmPending = null
  }

  // A pending confirmation belongs to the view that asked for it; never let
  // it survive a tab switch or a re-summon.
  onActiveTabChanged: root.closeConfirm()
  readonly property var tabs: [
    { id: "timer",    label: "Timer",    file: "views/TimerView.qml" },
    { id: "entries",  label: "Entries",  file: "views/EntriesView.qml" },
    { id: "clients",  label: "Clients",  file: "views/ClientsView.qml" },
    { id: "projects", label: "Projects", file: "views/ProjectsView.qml" },
    { id: "reports",  label: "Reports",  file: "views/ReportsView.qml" },
    { id: "invoices", label: "Invoices", file: "views/InvoicesView.qml" },
    { id: "settings", label: "Settings", file: "views/SettingsView.qml" }
  ]

  FloatingWindow {
    id: window
    title: "Quattro — Time Tracking"
    color: Color.background
    implicitWidth: 1100
    implicitHeight: 700
    minimumSize: Qt.size(860, 560)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide(root.pluginId)
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true
      // Window-level key gate: a Keys.BeforeItem handler on this ancestor
      // sees every key in the window before any other handler (focused
      // control included). Order:
      //   1. confirm dialog open → its handleKey owns Esc/arrows/Tab/Enter
      //   2. else the active view's handleKey, if it defines one (the
      //      Entries edit overlay closes on Esc)
      //   3. else fall through to the key catcher / focused control
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (confirmDialog.opened) {
          if (confirmDialog.handleKey(event)) event.accepted = true
          return
        }
        var view = viewLoader.item
        if (view && typeof view.handleKey === "function" && view.handleKey(event))
          event.accepted = true
      }

      // Esc closes the window only while no dialog and no view input own the
      // keyboard.
      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: confirmDialog.opened
          || (viewLoader.item ? viewLoader.item.inputActive === true : false)
        onCloseRequested: root.requestClose()
      }

      Row {
        anchors.fill: parent


        // ---- sidebar -------------------------------------------------------
        Item {
          id: sidebar
          width: Style.space(190)
          height: parent.height

          Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Qt.darker(Color.foreground, 2.2)
          }

          Column {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            anchors.topMargin: Style.space(14)
            spacing: Style.space(4)

            Column {
              width: parent.width
              spacing: Style.space(1)
              Text {
                text: "Quattro"
                color: Color.foreground
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Text {
                text: "time tracking"
                color: Color.muted
                font.pixelSize: Style.font.caption
              }
            }

            Item { height: Style.space(8) }

            Repeater {
              model: root.tabs
              Button {
                required property var modelData
                width: parent.width
                text: modelData.label
                leftAlign: true
                focusable: true
                selected: root.activeTab === modelData.id
                onClicked: root.activeTab = modelData.id
              }
            }
          }
        }

        // ---- main -----------------------------------------------------------
        Column {
          width: parent.width - sidebar.width
          height: parent.height

          // Header: title + live status chip.
          Item {
            id: header
            width: parent.width
            height: Style.space(56)

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.leftMargin: Style.space(16)
              anchors.rightMargin: Style.space(16)
              spacing: Style.space(12)

              Text {
                text: "Quattro — Time Tracking"
                color: Color.foreground
                font.pixelSize: Style.font.heading
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Item { width: 1 }

              Row {
                spacing: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: width / 2
                  color: root.service && root.service.running
                    ? (root.service.paused ? Qt.darker(Color.foreground, 1.4) : Color.accent)
                    : Qt.darker(Color.foreground, 1.8)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: {
                    var s = root.service
                    if (!s) return ""
                    if (s.running && s.active) {
                      var desc = s.active.description !== "" ? s.active.description : ""
                      var client = s.clientName(s.active.clientId)
                      var name = desc !== "" ? (client !== "" ? client + " — " + desc : desc)
                                          : (client !== "" ? client : "-")
                      return name + " · " + s.elapsedLabel + (s.paused ? " (paused)" : "")
                    }
                    return "Today " + s.fmtHM(s.daySeconds)
                  }
                  color: Color.muted
                  font.pixelSize: Style.font.subtitle
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // Single active view; switching tabs destroys the old one. All
          // persistent state lives in the service and on disk, so filters
          // resetting on tab switch is expected (documented).
          Loader {
            id: viewLoader
            width: parent.width
            height: parent.height - header.height
            source: {
              for (var i = 0; i < root.tabs.length; i++)
                if (root.tabs[i].id === root.activeTab)
                  return Qt.resolvedUrl(root.tabs[i].file)
              return ""
            }
            onLoaded: {
              if (item) {
                item.service = root.service
                item.dashboard = root
              }
            }
          }
        }
      }

      // Declared last so it draws above sidebar + view. Fills the window so
      // the card centers over the whole window (shell-kit pattern: see
      // Menu/Clipboard panels).
      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent

        onConfirmed: {
          var pending = root.confirmPending
          root.closeConfirm()
          if (pending) pending()
        }
        onCanceled: root.closeConfirm()
      }
    }
  }
}
