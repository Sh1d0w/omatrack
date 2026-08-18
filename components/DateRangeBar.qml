import QtQuick
import qs.Commons
import qs.Ui

// Date interval picker: six presets (Today, Yesterday, 7 days, This month,
// Last month, All) plus manual from/to fields. Emits
// `changed(from, to, preset)` with preset "" for manual entry. The presets
// are computed in the local calendar; the service supplies date formatting
// so there is one implementation of the date helpers.
Item {
  id: root
  width: parent ? parent.width : Style.space(460)

  required property var service

  property string from: ""
  property string to: ""
  property string currentPreset: "today"
  // True while either manual date field owns keyboard focus.
  readonly property bool fieldActive: _fromField.activeFocus || _toField.activeFocus

  signal changed(string from, string to, string preset)

  Row {
    anchors.fill: parent
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

    Item { width: Style.space(10) }

    TextField {
      id: _fromField
      width: Style.space(96)
      placeholderText: "YYYY-MM-DD"
      text: root.from
      onTextChanged: { if (text !== root.from) root.from = text }
      onAccepted: {
        root.currentPreset = ""
        root.changed(root.from, root.to, "")
      }
    }

    Text {
      text: "→"
      color: Color.muted
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }

    TextField {
      id: _toField
      width: Style.space(96)
      placeholderText: "YYYY-MM-DD"
      text: root.to
      onTextChanged: { if (text !== root.to) root.to = text }
      onAccepted: {
        root.currentPreset = ""
        root.changed(root.from, root.to, "")
      }
    }
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
    // Typing into a field breaks its text binding; set the text explicitly so
    // the controls always show the selected preset's range.
    _fromField.text = r[0]
    _toField.text = r[1]
    root.currentPreset = preset
    root.changed(r[0], r[1], preset)
  }
}
