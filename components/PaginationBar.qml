import QtQuick
import qs.Commons
import qs.Ui

// Pager shared by every table view: ← / → around "Showing X–Y of Z".
// The page size is fixed (service.pageSize, 15). The view owns the offset
// and re-queries (server-paginated) or re-slices (in-service lists) on
// prev/next.
Item {
  id: root

  property int offset: 0
  property int limit: 15
  property int total: 0
  property string emptyText: "No rows"

  signal prevRequested()
  signal nextRequested()

  implicitWidth: bar.implicitWidth
  implicitHeight: bar.implicitHeight

  Row {
    id: bar
    spacing: Style.space(8)

    Button {
      text: "←"
      focusable: true
      enabled: root.offset > 0
      onClicked: root.prevRequested()
    }

    Text {
      textFormat: Text.PlainText
      text: root.total > 0
        ? "Showing " + (root.offset + 1) + "–"
          + Math.min(root.offset + root.limit, root.total) + " of " + root.total
        : root.emptyText
      color: Color.muted
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }

    Button {
      text: "→"
      focusable: true
      enabled: root.offset + root.limit < root.total
      onClicked: root.nextRequested()
    }
  }
}
