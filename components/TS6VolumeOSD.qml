import QtQuick
import qs.Common
import qs.Widgets

DankOSD {
    id: root
    property var service: null
    property real _vol: -1

    osdWidth: Math.min(240, screenWidth - Theme.spacingM * 2)
    osdHeight: 44
    autoHideInterval: 1500
    enableMouseInteraction: false

    Connections {
        target: root.service
        function onVolumeUserChanged(v) {
            root._vol = Math.max(0, Math.min(1, v))
            root.show()
        }
    }

    content: Item {
        anchors.fill: parent

        Row {
            anchors.centerIn: parent
            spacing: Theme.spacingS + Theme.spacingXS

            DankIcon {
                width: Theme.iconSize
                height: Theme.iconSize
                name: root._vol <= 0 ? "headset_off" : "headset_mic"
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: 130
                height: 16
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: parent.width
                    height: 12
                    radius: 6
                    color: Theme.withAlpha(Theme.primary, 0.24)
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        id: fillBar
                        width: parent.width * Math.max(0, Math.min(1, root._vol))
                        height: parent.height
                        radius: 6
                        topRightRadius: { const trackW = parent.width; return (fillBar.width >= trackW - 0.5) ? 6 : 0 }
                        bottomRightRadius: { const trackW = parent.width; return (fillBar.width >= trackW - 0.5) ? 6 : 0 }
                        color: Theme.primary
                        Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }
}
