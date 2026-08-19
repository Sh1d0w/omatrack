import QtQuick
import qs.Commons
import qs.Ui

// Date range control: six presets plus From/To calendar pickers
// (DatePicker). Emits `changed(from, to, preset)` with preset "" when a
// date is picked by hand. The presets are computed in the local calendar;
// the service supplies date formatting so there is one implementation of
// the date helpers.
//
// Row 1: the preset buttons. Row 2: the From/To pickers, each a labeled
// read-only field that opens a month-grid popup (see DatePicker); hidden
// with `showPickers: false` (Reports keeps its range preset-only). Picking
// a date breaks the active preset (manual range).
Column {
  id: root
  property int naturalWidth:
    Math.max(presetsRow.implicitWidth, manualRow.implicitWidth)
  width: naturalWidth
  height: showPickers ? implicitHeight : presetsRow.implicitHeight
  spacing: Style.space(8)
  // Manual From/To pickers (default on). Reports hides them: its range is
  // preset-only; manual dates are picked in Entries / invoices / entry form.
  property bool showPickers: true

  required property var service

  property string from: ""
  property string to: ""
  property string currentPreset: "today"
  // True while a calendar picker owns the keyboard; the host view keeps the
  // window's key catcher blocked then.
  readonly property bool fieldActive: fromPicker.popupOpen || toPicker.popupOpen

  signal changed(string from, string to, string preset)

  Row {
    id: presetsRow
    spacing: Style.space(6)

    Repeater {
      model: [
        { id: "today", label: "Today" },
        { id: "yesterday", label: "Yesterday" },
        { id: "7d", label: "7 days" },
        { id: "month", label: "This month" },
        { id: "lastmonth", label: "Last month" },
        { id: "all", label: "All" }
      ]
      Button {
        required property var modelData
        text: modelData.label
        fontSize: Style.font.bodySmall
        selected: root.currentPreset === modelData.id
        onClicked: root.applyPreset(modelData.id)
      }
    }
  }

  Row {
    id: manualRow
    width: parent.width
    height: root.showPickers ? implicitHeight : 0
    spacing: Style.space(8)
    visible: root.showPickers

    DatePicker {
      id: fromPicker
      label: "From"
      date: root.from
      onChanged: function(d) { root._pick(d, "from") }
    }

    DatePicker {
      id: toPicker
      label: "To"
      date: root.to
      onChanged: function(d) { root._pick(d, "to") }
    }
  }

  // A hand-picked date is a manual range, whatever the previous preset was.
  function _pick(d, which) {
    if (which === "from") root.from = d
    else root.to = d
    root.currentPreset = ""
    root.changed(root.from, root.to, "")
  }

  // Returns [from, to] for a preset id; null for unknown ids.
  function presetRange(preset) {
    var now = new Date()
    var f = function(d) { return root.service.localDateStr(d) }
    var d
    if (preset === "today") {
      return [f(now), f(now)]
    }
    if (preset === "yesterday") {
      d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
      return [f(d), f(d)]
    }
    if (preset === "7d") {
      d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6)
      return [f(d), f(now)]
    }
    if (preset === "month") {
      return [f(new Date(now.getFullYear(), now.getMonth(), 1)), f(now)]
    }
    if (preset === "lastmonth") {
      var first = new Date(now.getFullYear(), now.getMonth() - 1, 1)
      var last = new Date(now.getFullYear(), now.getMonth(), 0)
      return [f(first), f(last)]
    }
    if (preset === "all") return ["", ""]
    return null
  }

  function applyPreset(preset) {
    var r = root.presetRange(preset)
    if (!r) return
    root.from = r[0]
    root.to = r[1]
    root.currentPreset = preset
    root.changed(r[0], r[1], preset)
  }
}
