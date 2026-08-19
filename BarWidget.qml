import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar label for the current client/task + live elapsed time, and the host
// for the quick-start popup.
//
// Idle shows a static clock icon (U+F2F2, Nerd Font);
// running shows "task  H:MM:SS", re-evaluated every second via the
// service's clock-driven `elapsedLabel`; paused freezes the label with a
// "(paused)" suffix. Left click reveals the popup (start/pause/resume/stop
// + new-task form + dashboard).
BarWidget {
  id: root
  moduleName: "io.github.sh1d0w.omatrack"

  // The plugin's headless engine (singleton, in-process). The binding
  // re-evaluates when the shell reassigns its service map.
  readonly property var service:
    bar ? bar.shell.serviceFor("io.github.sh1d0w.omatrack") : null

  // ---- Popup. Shape contract for shell summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget
  //      root; popoutSwitchClosing/closeForPopoutSwitch let the widget stand
  //      in for the panel as the bar's popout identity.
  readonly property bool opened: popupLoader.item ? popupLoader.item.opened === true : false

  function open() { if (popupLoader.item) popupLoader.item.open() }
  function close() { if (popupLoader.item) popupLoader.item.close() }
  function togglePanel() { if (popupLoader.item) popupLoader.item.toggle() }

  readonly property bool popoutSwitchClosing:
    popupLoader.item ? popupLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (popupLoader.item) popupLoader.item.closeForPopoutSwitch()
  }

  function injectPopup() {
    var target = popupLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  // The widget fills its slot with a text label in a padded slot, so the
  // open-panel indicator takes the label width (clock convention).
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight:
    Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPopup()
  onSettingsChanged: injectPopup()
  onServiceChanged: injectPopup()

  Loader {
    id: popupLoader
    active: true
    source: Qt.resolvedUrl("Popup.qml")
    visible: false
    onLoaded: {
      root.injectPopup()
      Qt.callLater(root.injectPopup)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    horizontalMargin: 8.5
    verticalPadding: 6
    active: isRunning
    // The idle glyph draws slightly smaller than the bar icon size: the
    // Nerd Font clock renders larger than the old geometric glyph; the
    // running label uses the body font.
    fontSize: isRunning ? Style.font.body : Math.round(Style.bar.iconFont * 0.9)

    readonly property bool isRunning: root.service ? root.service.running : false

    text: {
      var s = root.service
      if (!s) return ""
      if (s.running && s.active) {
        var label = s.active.description !== "" ? s.active.description : s.clientName(s.active.clientId)
        if (label === "") label = "-"
        return label + "  " + s.elapsedLabel + (s.paused ? "  (paused)" : "")
      }
      return ""
    }

    tooltipText: {
      var s = root.service
      if (!s) return ""
      if (s.running && s.active) {
        return s.clientName(s.active.clientId)
          + (s.active.description !== "" ? " — " + s.active.description : "")
          + " · " + s.elapsedLabel
          + (s.paused ? " · paused" : "")
          + " · " + (s.active.billable ? "billable" : "non-billable")
      }
      return s.daySeconds > 0
        ? "Today " + s.fmtHM(s.daySeconds) + " · start a task"
        : "No active timer"
    }

    onPressed: function(code) {
      if (code === Qt.LeftButton) root.togglePanel()
    }
  }
}
