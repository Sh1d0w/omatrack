import QtQuick
import qs.Commons
import qs.Ui

// Pager shared by every table view: ← / → around "Showing X–Y of Z", plus
// the global page-size selector. The dropdown writes settings.pageSize,
// which every table reads back through service.pageSize; the owning view
// resets its offset to page 1 on the change. The view owns the offset and
// re-queries (server-paginated) or re-slices (in-service lists) on
// prev/next.
Item {
  id: root

  property int offset: 0
  property int limit: 50
  property int total: 0
  property string emptyText: "No rows"
  property var service: null

  signal prevRequested()
  signal nextRequested()

  // True while the page-size popup owns the keyboard; the view ORs this
  // into its inputActive.
  readonly property bool pageSizePopupOpen: pageDrop.popupOpen

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

    Dropdown {
      id: pageDrop
      width: Style.space(110)
      value: String(root.limit)
      options: [
        { value: "10", label: "10 / page" },
        { value: "25", label: "25 / page" },
        { value: "50", label: "50 / page" },
        { value: "100", label: "100 / page" }
      ]
      onChanged: function(v) {
        if (root.service)
          root.service.saveSettings({ pageSize: parseInt(v, 10) })
      }
    }
  }
}
