import QtQuick
import qs.Commons
import qs.Ui

// One time entry in a list: date + time, client — project, description,
// a billable mark, duration, and Edit / Del actions. Clicking anywhere on
// the row (outside the buttons) requests editing.
Item {
  id: root
  implicitHeight: Style.space(52)

  required property var service
  required property var modelData

  signal editRequested()
  signal deleteRequested()

  readonly property var e: modelData

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
        text: {
          var d = new Date(Date.parse(e.start))
          if (isNaN(d.getTime())) return ""
          return Qt.formatDateTime(d, "d MMM") + " " + Qt.formatDateTime(d, "HH:mm")
            + "  ·  " + root.service.clientName(e.clientId)
            + " — " + root.service.projectName(e.projectId)
        }
        color: Color.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        elide: Text.ElideRight
        text: e.description !== "" ? e.description : "-"
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: rightRow
      spacing: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        textFormat: Text.PlainText
        visible: e.billable === true
        text: "billable"
        color: Color.accent
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: root.service.fmtHMS(e.seconds)
        color: Color.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }

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
