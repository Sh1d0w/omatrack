import QtQuick
import qs.Commons
import qs.Ui

// A table's empty state: one muted line centered in the table's viewport
// while it has no rows. Every table view drops one into its ListView — a
// direct Flickable child lives in the viewport coordinate system, so it
// stays centered and never scrolls with content. The host shows it only
// while the (filtered) row count is zero.
Text {
  textFormat: Text.PlainText
  id: root

  property string message: "No rows"

  text: root.message
  color: Color.muted
  font.pixelSize: Style.font.body
  anchors.centerIn: parent
}
