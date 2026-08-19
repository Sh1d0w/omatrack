import QtQuick
import qs.Commons
import qs.Ui

// One client in a list: name (bold) + "N projects · added YYYY-MM-DD"
// (muted), Edit / Del actions on the right. Clicking anywhere on the row
// (outside the buttons) requests editing.
Item {
  id: root
  implicitHeight: Style.space(52)

  required property var service
  required property var modelData

  signal editRequested()
  signal deleteRequested()

  readonly property var c: modelData

  function projectCount() {
    var n = 0
    var ps = root.service.projects
    for (var i = 0; i < ps.length; i++)
      if (ps[i].clientId === c.id) n++
    return n
  }

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
        width: parent.width
        elide: Text.ElideRight
        text: c.name
        color: Color.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: root.projectCount() + " projects"
          + (c.createdAt ? " · added " + root.service.localDateStr(new Date(c.createdAt)) : "")
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
