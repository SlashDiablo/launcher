import QtQuick 2.12				//Item
import QtQuick.Layouts 1.3		//ColumnLayout
import QtGraphicalEffects 1.0   //OpacityMask

Item {
    id: newsTableBox
	width: parent.width
    height: parent.height

    anchors.top: parent.top
    anchors.right: parent.right

	ColumnLayout {
		anchors.fill: parent
		anchors.leftMargin: 15
		anchors.rightMargin: 10
		anchors.topMargin: 15
		
		ListView {
			id: newsList
			spacing: 0
			visible: (!news.loading && !news.error)

			// The list is taller than the space it gets, so it scrolls and is
			// clipped to its own bounds instead of drawing over the launch
			// controls below it.
			interactive: true
			clip: true
			boundsBehavior: Flickable.StopAtBounds

			Layout.fillWidth: true
			Layout.fillHeight: true

			model: news.items
			delegate: NewsItemDelegate{}

			// Fade the last of the list out rather than cutting it off, so it
			// reads as continuing past the bottom edge.
			layer.enabled: true
			layer.effect: OpacityMask {
				maskSource: Rectangle {
					width: newsList.width
					height: newsList.height
					gradient: Gradient {
						GradientStop { position: 0.00; color: "#ffffffff" }
						GradientStop { position: 0.85; color: "#ffffffff" }
						GradientStop { position: 1.00; color: "#00ffffff" }
					}
				}
			}
		}

		// Show if we're loading on if there's been an error.
		Item {
			Layout.fillWidth: true
			Layout.fillHeight: true
			visible: (news.loading || news.error)

			// Loading circle.			
			CircularProgress {
				size: 25
				anchors.centerIn: parent
				visible: news.loading
			}

			// Error item.
			Item {
				anchors.centerIn: parent
				visible: news.error
				height: 100

				Title {
					color: "#ffffff"
					topPadding: 30
					text: "Unable to get news"
					font.pixelSize: 13
					anchors.horizontalCenter: parent.horizontalCenter
				}
			}
		}
	}

	Component.onCompleted: {
		news.items.clear()
		news.getNews()
	}
}
