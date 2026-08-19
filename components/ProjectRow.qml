import QtQuick
import qs.Commons
import qs.Ui

// One project in a list: name (bold) + owning client (muted) below it,
// Edit / Del actions on the right. Clicking anywhere on the row (outside
// the buttons) requests editing.
Item {
  id: root
  implicitHeight: Style.space(52)

  required property var service
  required property var modelData

  signal editRequested()
  signal deleteRequested()

  readonly property var p: modelData

  // Row-wide hover + click first (lowest), so the buttons above it still
  // receive their own clicks.
  MouseArea {
    id: rowHover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.editRequested()

    Rectangle {
      anchors.fill: parent
      color: rowHover.containsMouse
        ? Style.hoverFillFor(Color.foreground, Color.accent)
        : "transparent"
      Behavior on color { ColorAnimation { duration: 80 } }
    }
  }

  Row {
    anchors.fill: parent
    spacing: Style.space(8)

    Column {
      width: parent.width - rightRow.width - parent.spacing
      spacing: Style.space(2)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        textFormat: Text.PlainText
        width: parent.width
        elide: Text.ElideRight
        text: p.name
        color: Color.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        elide: Text.ElideRight
        text: root.service.clientName(p.clientId)
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: rightRow
      spacing: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter

      Button {
        text: "Edit"
        fontSize: Style.font.bodySmall
        onClicked: root.editRequested()
      }

      Button {
        text: "Del"
        fontSize: Style.font.bodySmall
        foreground: Color.urgent
        onClicked: root.deleteRequested()
      }
    }
  }
}
