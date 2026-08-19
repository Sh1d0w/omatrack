import QtQuick
import qs.Commons
import qs.Ui

// One report row: the group's label (bold) + "N entries · billable HH:MM
// (· non-billable HH:MM)" (muted), a share hairline (the row's share of
// the report's total — same track/fill pair as the shell's OSD bar), and
// the row's HH:MM total on the right. Not interactive: a report row is a
// read-only aggregate, so no hover/click area.
Item {
  id: root
  implicitHeight: Style.space(52)

  required property var service
  required property var modelData
  // The whole (unpaginated) report total; the share bar is relative to it,
  // so bars are comparable across pages.
  property int totalSeconds: 0

  readonly property var r: modelData
  readonly property int nonBillableSeconds: Math.max(0, r.seconds - r.billableSeconds)
  readonly property real share:
    root.totalSeconds > 0 ? r.seconds / root.totalSeconds : 0

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
        text: r.label
        color: Color.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        elide: Text.ElideRight
        text: r.count + (r.count === 1 ? " entry" : " entries")
          + " · billable " + root.service.fmtDur(r.billableSeconds)
          + (root.nonBillableSeconds > 0
              ? " · non-billable " + root.service.fmtDur(root.nonBillableSeconds)
              : "")
        color: Color.muted
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        width: parent.width
        height: Style.space(4)
        color: Util.alpha(Color.foreground, 0.08)
        Rectangle {
          height: parent.height
          width: parent.width * root.share
          color: Color.accent
          Behavior on width {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      id: rightRow
      text: root.service.fmtDur(r.seconds)
      color: Color.foreground
      font.pixelSize: Style.font.subtitle
      font.bold: true
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
