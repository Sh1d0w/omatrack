import QtQuick
import qs.Commons
import qs.Ui

// Labeled single-line input for form tabs (used by the Settings view):
// a body-size label above, the kit TextField in the middle, a muted
// helper line below. The host owns the text (binds it, reads it back),
// listens to textChanged for dirty tracking, and reads `focused` to
// keep the window's Esc-to-close blocked while this field owns the
// keyboard.
Column {
  id: root

  property string label: ""
  property string helper: ""
  property alias text: field.text
  property alias placeholderText: field.placeholderText
  readonly property bool focused: field.activeFocus

  width: parent ? parent.width : Style.spacing.numberFieldWidth
  spacing: Style.space(3)

  Text {
    textFormat: Text.PlainText
    text: root.label
    color: Color.foreground
    font.pixelSize: Style.font.body
  }

  TextField {
    id: field
    width: parent.width
  }

  Text {
    textFormat: Text.PlainText
    visible: root.helper !== ""
    text: root.helper
    color: Color.muted
    font.pixelSize: Style.font.caption
    width: parent.width
    wrapMode: Text.Wrap
  }
}
