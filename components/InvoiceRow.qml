import QtQuick
import qs.Commons
import qs.Ui

// One generated invoice: number · client (bold) + "from → to · created
// YYYY-MM-DD" (muted), the total and an Open action on the right.
// Clicking anywhere on the row (outside the button) opens the file.
Item {
  id: root
  implicitHeight: Style.space(52)

  required property var service
  required property var modelData

  signal openRequested()

  readonly property var inv: modelData

  // Row-wide hover + click first (lowest), so the button above it still
  // receives its own clicks.
  MouseArea {
    id: rowHover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.openRequested()

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
        text: inv.number + " · " + inv.client
        color: Color.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: inv.from + " → " + inv.to + " · created "
          + (inv.createdAt ? root.service.localDateStr(new Date(inv.createdAt)) : "")
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: rightRow
      spacing: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        text: Number(inv.total).toFixed(2)
          + (root.service.settings && root.service.settings.currency
              ? " " + root.service.settings.currency
              : "")
        color: Color.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }

      Button {
        text: "Open"
        fontSize: Style.font.bodySmall
        onClicked: root.openRequested()
      }
    }
  }
}
