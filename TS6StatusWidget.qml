import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "./components"

PluginComponent {
    id: root

    // Hide the whole pill via DMS's BasePill hidden state once not in a channel.
    visibilityCommand: "false"
    Connections {
        target: svc
        function onNotifyTickChanged() {
            root.conditionVisible = root.showWhenConnected;
        }
    }
    Component.onCompleted: root.conditionVisible = root.showWhenConnected

    // ----- Settings wiring -----
    property string hostSetting: pluginData.host || "127.0.0.1"
    property int portSetting: parseInt(pluginData.port || "5899", 10) || 5899
    property string micKey: pluginData.micKey || "dms.ts6.mic"
    property string muteKey: pluginData.muteKey || "dms.ts6.mute"
    property string leaveKey: pluginData.leaveKey || "dms.ts6.leave"
    property bool showAvatars: pluginData.showAvatars !== false
    property bool showVolume: pluginData.showVolume !== false
    property bool showServerName: pluginData.showServerName === true
    property bool showCurrentChannel: pluginData.showCurrentChannel === true
    property bool showChannelCount: pluginData.showChannelCount === true
    property bool debugLog: pluginData.debugLog === true

    // Slightly larger avatar shown on the capsules, plus a speaking ring.
    readonly property real pillAvatarSize: 30

    // Width occupied by the three control buttons on the pill. The third
    // (leave) button grows when it shows the awayMessage text instead of only
    // the door icon, so we estimate its width (Chinese chars are ~11px wide).
    readonly property int _leaveBtnW: root.ts6Service.selfAway && root.ts6Service.selfAwayMessage !== ""
        ? Math.ceil(root.ts6Service.selfAwayMessage.length * 11) + Theme.spacingXS
        : 20
    readonly property real pillControlsWidth: root.showWhenConnected ? 20 + 20 + root._leaveBtnW : 0

    // True when we are connected to a server and are inside a channel. This is
    // what makes the whole pill appear/disappear (empty channel still shows).
    readonly property bool showWhenConnected: root.ts6Service.notifyTick >= 0 && root.ts6Service.hasActiveConnection && root.ts6Service.selfChannelId > 0

    // ----- Minimal i18n (mirrors the settings page keys) -----
    readonly property string _lang: pluginData.language || "zh"
    readonly property var _zh: ({
        "refreshCache": "刷新头像和昵称缓存",
        "notConnected": "未连接到 TeamSpeak（请确认已安装 TS6 并在 设置 → Remote Apps 中启用）",
        "needAuth": "请在 TeamSpeak → 设置 → Remote Apps → 权限请求 中批准本应用以完成授权",
        "serverLabel": "服务器：",
        "channelLabel": "频道：",
        "countLabel": "人数：",
        "unknownUser": "未知用户",
        "talking": "正在说话",
        "micMuted": "麦克风已静音",
        "outputMuted": "已静音（听不到）",
        "awayStatus": "离开",
        "notConnectedTitle": "未连接"
    })
    readonly property var _en: ({
        "refreshCache": "Refresh avatar & nickname cache",
        "notConnected": "Not connected to TeamSpeak (make sure TS6 is installed and Remote Apps is enabled)",
        "needAuth": "Approve this app in TeamSpeak → Settings → Remote Apps → Permission Requests",
        "serverLabel": "Server: ",
        "channelLabel": "Channel: ",
        "countLabel": "Members: ",
        "unknownUser": "Unknown user",
        "talking": "Talking",
        "micMuted": "Microphone muted",
        "outputMuted": "Muted (can't hear)",
        "awayStatus": "Away",
        "notConnectedTitle": "Not connected"
    })
    readonly property var _dict: root._lang === "en" ? root._en : root._zh
    function t(key) { return root._dict[key] !== undefined ? root._dict[key] : key }

    // ----- The TS6 status service (one instance per widget) -----
    readonly property var ts6Service: svc
    TS6Service {
        id: svc
    }

    // ----- Forward settings into the service -----
    Binding { target: ts6Service; property: "serverHost"; value: root.hostSetting }
    Binding { target: ts6Service; property: "serverPort"; value: root.portSetting }
    Binding { target: ts6Service; property: "debugLog"; value: root.debugLog }

    // The mic / mute / volume functions work by sending discrete virtual key
    // presses that you bind in TeamSpeak -> Settings -> Key Bindings to the
    // desired action (e.g. "Toggle Microphone"). The button identifiers below
    // can be customised in this plugin's settings.

    // ----- First run / auth flow -----
    readonly property bool showSetupHint: !root.ts6Service.authenticated && root.ts6Service.connected

    // Retry the socket when settings change / first enable.
    function reconnect() {
        root.ts6Service.reconnect();
    }

    // ----- Actions -----
    function toggleMic() {
        root.ts6Service.triggerButton(root.micKey);
    }
    function toggleMute() {
        root.ts6Service.triggerButton(root.muteKey);
    }
    function leave() {
        root.ts6Service.triggerButton(root.leaveKey);
    }

    // Small circular icon button used on the pills.
    component PillActionButton: Rectangle {
        id: btnRoot
        property string icon: ""
        property string text: ""
        property var action: null
        property color tint: Theme.surfaceText
        property color highlightColor: Theme.primary
        property bool highlighted: false
        width: text !== "" ? textItem.width + Theme.spacingXS : 20
        height: 20
        radius: text !== "" ? 4 : height / 2
        color: (hoverArea.containsMouse || btnRoot.highlighted) ? Theme.surfaceContainerHighest : Theme.withAlpha(Theme.surfaceContainerHighest, 0.2)
        border.width: text !== "" ? 1 : 0
        border.color: text !== "" ? btnRoot.highlightColor : "transparent"
        StyledText {
            id: textItem
            anchors.centerIn: parent
            visible: btnRoot.text !== ""
            text: btnRoot.text
            color: (hoverArea.containsMouse || btnRoot.highlighted) ? btnRoot.highlightColor : btnRoot.tint
            font.pixelSize: 11
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        DankIcon {
            anchors.centerIn: parent
            name: btnRoot.icon
            size: 15
            visible: btnRoot.text === ""
            color: (hoverArea.containsMouse || btnRoot.highlighted) ? btnRoot.highlightColor : btnRoot.tint
        }
        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (btnRoot.action) btnRoot.action()
            }
        }
    }

    // =============================================================
    // Vertical pill (icon + counts; mic-muted dot indicator)
    // =============================================================
    verticalBarPill: Component {
        Item {
            id: vPill
            clip: true
            visible: root.showWhenConnected
            implicitWidth: root.showWhenConnected ? root.pillAvatarSize : 0
            implicitHeight: root.ts6Service.notifyTick >= 0 && root.ts6Service.channelClients && root.ts6Service.channelClients.length > 0 ? root.pillAvatarSize * root.ts6Service.channelClients.length + Theme.spacingXS * Math.max(0, root.ts6Service.channelClients.length - 1) : 0

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                onWheel: (w) => {
                    if (!root.ts6Service.tsVolumeKnown) return
                    var step = (w.angleDelta && w.angleDelta.y !== 0) ? (w.angleDelta.y / 120) * 0.05 : ((w.pixelDelta && w.pixelDelta.y !== 0) ? w.pixelDelta.y * 0.01 : 0)
                    if (step === 0) return
                    root.ts6Service.setTsVolume01(Math.max(0, Math.min(1, root.ts6Service.tsVolume01 + step)))
                    w.accepted = true
                }
            }

            Column {
                spacing: Theme.spacingXS
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: root.ts6Service.notifyTick >= 0 ? root.ts6Service.channelClients : []
                    delegate: Item {
                        width: root.pillAvatarSize
                        height: root.pillAvatarSize
                        readonly property bool talking: modelData.talkStatus === 1 || modelData.talkStatus === 3 || modelData.properties.flagTalking === true
                        readonly property bool isSelf: modelData.id === root.ts6Service.activeSelfId()
                        readonly property bool away: !!modelData.properties.away
                        DankCircularImage {
                            anchors.fill: parent
                            color: "transparent"
                            imageSource: root.showAvatars ? root.ts6Service.cachedAvatar(modelData) : ""
                            fallbackIcon: "person"
                            cacheImages: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: width / 2
                            color: parent.away ? Theme.withAlpha(Theme.surfaceVariant, 0.35) : "transparent"
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: parent.talking ? 2 : 0
                            border.color: parent.talking ? Theme.primary : "transparent"
                        }
                        Item {
                            width: 18
                            height: 18
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: -2
                            anchors.bottomMargin: -2
                            visible: modelData.properties.inputMuted ||
                                     modelData.properties.outputMuted
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "#1f1f27"
                            }
                            DankIcon {
                                anchors.fill: parent
                                name: modelData.properties.outputMuted && !modelData.properties.inputMuted ? "volume_off" : "mic_off"
                                size: 12
                                color: Theme.primary
                            }
                        }
                    }
                }
            }
        }
    }

    // =============================================================
    // Horizontal pill
    // =============================================================
    horizontalBarPill: Component {
        Item {
            id: hPill
            clip: true
            visible: root.showWhenConnected
            implicitWidth: root.showWhenConnected ? (root.ts6Service.channelClients && root.ts6Service.channelClients.length > 0 ? root.pillAvatarSize * root.ts6Service.channelClients.length + Theme.spacingXS * root.ts6Service.channelClients.length : 0) + root.pillControlsWidth + 0 : 0
            implicitHeight: root.pillAvatarSize

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                onWheel: (w) => {
                    if (!root.ts6Service.tsVolumeKnown) return
                    var step = (w.angleDelta && w.angleDelta.y !== 0) ? (w.angleDelta.y / 120) * 0.05 : ((w.pixelDelta && w.pixelDelta.y !== 0) ? w.pixelDelta.y * 0.01 : 0)
                    if (step === 0) return
                    root.ts6Service.setTsVolume01(Math.max(0, Math.min(1, root.ts6Service.tsVolume01 + step)))
                    w.accepted = true
                }
            }

            Row {
                spacing: 0
                anchors.verticalCenter: parent.verticalCenter
                visible: root.showWhenConnected

                Row {
                    spacing: 0
                    anchors.verticalCenter: parent.verticalCenter
                    PillActionButton {
                        icon: (root.ts6Service.selfInputMuted || root.ts6Service.selfAway) ? "mic_off" : "mic"
                        action: root.toggleMic
                        highlighted: root.ts6Service.selfInputMuted || root.ts6Service.selfAway || root.ts6Service.selfTalking
                    }
                    PillActionButton {
                        icon: root.ts6Service.selfOutputMuted ? "volume_off" : "volume_up"
                        action: root.toggleMute
                        highlighted: root.ts6Service.selfOutputMuted
                    }
                    PillActionButton {
                        icon: root.ts6Service.selfAway ? "door_front" : "door_open"
                        text: root.ts6Service.selfAway ? root.ts6Service.selfAwayMessage : ""
                        action: root.leave
                        tint: (root.ts6Service.selfAway && root.ts6Service.selfOutputMuted) ? "#ff8b04" : Theme.surfaceText
                        highlightColor: (root.ts6Service.selfAway && root.ts6Service.selfOutputMuted) ? "#ff8b04" : Theme.primary
                        highlighted: root.ts6Service.selfAway
                    }
                }

                Row {
                    spacing: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: root.ts6Service.notifyTick >= 0 ? root.ts6Service.channelClients : []
                    delegate: Item {
                        width: root.pillAvatarSize
                        height: root.pillAvatarSize
                        readonly property bool talking: modelData.talkStatus === 1 || modelData.talkStatus === 3 || modelData.properties.flagTalking === true
                        readonly property bool isSelf: modelData.id === root.ts6Service.activeSelfId()
                        readonly property bool away: !!modelData.properties.away
                        DankCircularImage {
                            anchors.fill: parent
                            color: "transparent"
                            imageSource: root.showAvatars ? root.ts6Service.cachedAvatar(modelData) : ""
                            fallbackIcon: "person"
                            cacheImages: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: width / 2
                            color: parent.away ? Theme.withAlpha(Theme.surfaceVariant, 0.35) : "transparent"
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: parent.talking ? 2 : 0
                            border.color: parent.talking ? Theme.primary : "transparent"
                        }
                        Item {
                            width: 18
                            height: 18
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: -2
                            anchors.bottomMargin: -2
                            visible: modelData.properties.inputMuted ||
                                     modelData.properties.outputMuted
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "#1f1f27"
                            }
                            DankIcon {
                                anchors.fill: parent
                                name: modelData.properties.outputMuted && !modelData.properties.inputMuted ? "volume_off" : "mic_off"
                                size: 12
                                color: Theme.primary
                            }
                        }
                    }
                }
            }
            }
        }
    }

    // =============================================================
    // Popout panel
    // =============================================================
    popoutWidth: 460
    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: root.ts6Service.channelName || "TS6 Monitor"
            showCloseButton: true

            headerActions: Rectangle {
                property bool hovering: false
                width: 32
                height: 32
                radius: 16
                color: hoverArea.containsMouse ? Theme.surfaceContainerHigh : Theme.withAlpha(Theme.surfaceContainerHigh, 0)
                ToolTip.visible: hoverArea.containsMouse
                ToolTip.text: root.t("refreshCache")
                DankIcon {
                    anchors.centerIn: parent
                    name: "refresh"
                    size: Theme.iconSize - 4
                    color: hoverArea.containsMouse ? Theme.primary : Theme.surfaceText
                }
                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.ts6Service.refreshCache()
                    }
                }
            }

            Item {
                width: parent.width
                height: childrenRect.height

                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    padding: Theme.spacingM

                    // Auth / connection hint
                    StyledText {
                        text: {
                            if (!root.ts6Service.connected) return root.t("notConnected")
                            if (root.ts6Service.pendingAuth || !root.ts6Service.authenticated)
                                return root.t("needAuth")
                            return ""
                        }
                        visible: text !== ""
                        color: Theme.warning
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.Wrap
                        width: parent.width
                    }

                    // Optional info rows (controlled by settings, default off)
                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: root.showServerName || root.showCurrentChannel || root.showChannelCount

                        StyledText {
                            visible: root.showServerName
                            text: root.t("serverLabel") + (root.ts6Service.serverName || "—")
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: root.showCurrentChannel
                            text: root.t("channelLabel") + (root.ts6Service.channelName || "—")
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: root.showChannelCount
                            text: root.t("countLabel") + root.ts6Service.channelClientCount
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            // Member list
            Item {
                width: parent.width
                height: Math.min(channelList.contentHeight, 430)
                clip: false
                visible: root.ts6Service.connected

                DankListView {
                    id: channelList
                    anchors.fill: parent
                    spacing: Theme.spacingXS
                    model: root.ts6Service.notifyTick >= 0 ? root.ts6Service.channelClients : []
                    delegate: Rectangle {
                        id: row
                        width: ListView.view.width
                        height: 46
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        border.color: isTalking ? Theme.primary : "transparent"
                        border.width: isTalking ? 2 : 0

                        readonly property bool isTalking: modelData.talkStatus === 1 || modelData.talkStatus === 3 || modelData.properties.flagTalking === true
                        readonly property bool isSelf: modelData.id === root.ts6Service.activeSelfId()
                        readonly property bool away: !!modelData.properties.away
                        readonly property bool hasVolume: modelData.properties && modelData.properties.volumeModificator !== undefined && modelData.properties.volumeModificator !== null
                        readonly property double volDbValue: row.hasVolume ? Number(modelData.properties.volumeModificator) : 0
                        readonly property string volDbText: {
                            if (!row.hasVolume) return "—"
                            const d = row.volDbValue
                            return (d >= 0 ? "+" : "") + d.toFixed(1) + "dB"
                        }
                        readonly property double volFill: {
                            if (!row.hasVolume) return 0
                            return Math.max(0, Math.min(1, row.volDbValue / 10))
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingS

                            Item {
                                width: 34
                                height: 34
                                anchors.verticalCenter: parent.verticalCenter
                                DankCircularImage {
                                    anchors.fill: parent
                                    imageSource: root.showAvatars ? (root.ts6Service.cachedAvatar(modelData) || root.ts6Service.avatarUrl(modelData) || "") : ""
                                    fallbackIcon: "person"
                                    cacheImages: true
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: width / 2
                                    color: row.away ? Theme.withAlpha(Theme.surfaceVariant, 0.35) : "transparent"
                                }
                                Item {
                                    width: 20
                                    height: 20
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: -2
                                    anchors.bottomMargin: -2
                                    visible: modelData.properties.inputMuted ||
                                             modelData.properties.outputMuted
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "#1f1f27"
                                    }
                                    DankIcon {
                                        anchors.fill: parent
                                        name: modelData.properties.outputMuted && !modelData.properties.inputMuted ? "volume_off" : "mic_off"
                                        size: 14
                                        color: Theme.primary
                                    }
                                }
                            }

                            Row {
                                width: parent.width - 34 - 150 - Theme.spacingS * 3
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                StyledText {
                                    text: root.ts6Service.cachedNick(modelData) || modelData.displayName || modelData.properties.nickname || modelData.properties.name || root.t("unknownUser")
                                    color: row.isSelf ? Theme.primary : Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.bold: row.isSelf
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: {
                                        if (row.isTalking) return root.t("talking")
                                        if (modelData.properties.inputMuted) return root.t("micMuted")
                                        if (modelData.properties.outputMuted) return root.t("outputMuted")
                                        if (modelData.properties.away) return root.t("awayStatus")
                                        return ""
                                    }
                                    color: row.isTalking ? "#4CAF50" : (modelData.properties.inputMuted ? Theme.error : Theme.surfaceVariantText)
                                    font.pixelSize: Theme.fontSizeSmall
                                    visible: text !== ""
                                }
                            }

                            // Right side:
                            //  - self: adjustable TeamSpeak overall (PipeWire) volume
                            //  - others: read-only per-member volume bar
                            Item {
                                width: 150
                                height: parent.height
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.showVolume

                                // Self: adjustable overall TS volume
                                Row {
                                    anchors.fill: parent
                                    spacing: 6
                                    visible: row.isSelf

                                    Item {
                                        width: parent.width - 46
                                        height: parent.height
                                        M3WaveProgress {
                                            anchors.fill: parent
                                            value: root.ts6Service.tsVolumeKnown ? root.ts6Service.tsVolume01 : 0.5
                                            actualValue: value
                                            isPlaying: row.isTalking
                                            fillColor: Theme.primary
                                            trackColor: Theme.withAlpha(Theme.primary, 0.24)
                                            playheadColor: Theme.primary
                                            actualProgressColor: Theme.withAlpha(Theme.primary, 0.4)
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton
                                            onPressed: (m) => root.ts6Service.setTsVolume01(Math.max(0, Math.min(1, m.x / parent.width)))
                                            onPositionChanged: (m) => {
                                                if (pressed) root.ts6Service.setTsVolume01(Math.max(0, Math.min(1, m.x / parent.width)))
                                            }
                                            onWheel: (w) => {
                                                if (!root.ts6Service.tsVolumeKnown) return
                                                const step = w.angleDelta.y > 0 ? 0.01 : -0.01
                                                root.ts6Service.setTsVolume01(Math.max(0, Math.min(1, root.ts6Service.tsVolume01 + step)))
                                            }
                                        }
                                    }

                                    StyledText {
                                        width: contentWidth
                                        elide: Text.ElideNone
                                        text: root.ts6Service.tsVolumeKnown
                                            ? Math.round(root.ts6Service.tsVolume01 * 100) + "%"
                                            : "…"
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Item { width: 2; height: 1 }
                                }

                                // Others: read-only per-member volume
                                Row {
                                    anchors.fill: parent
                                    spacing: 6
                                    visible: !row.isSelf

                                    Item {
                                        width: parent.width - 46
                                        height: parent.height
                                        M3WaveProgress {
                                            anchors.fill: parent
                                            value: row.volFill
                                            actualValue: value
                                            isPlaying: row.isTalking
                                            fillColor: Theme.primary
                                            trackColor: Theme.withAlpha(Theme.primary, 0.24)
                                            playheadColor: Theme.primary
                                            actualProgressColor: Theme.withAlpha(Theme.primary, 0.4)
                                        }
                                    }

                                    StyledText {
                                        width: contentWidth
                                        elide: Text.ElideNone
                                        text: row.volDbText
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                        horizontalAlignment: Text.AlignLeft
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty / disconnected state
            Item {
                visible: !root.ts6Service.connected
                anchors.fill: parent
                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    DankIcon { name: "group_off"; size: 36; color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
                    StyledText { text: root.t("notConnectedTitle"); color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
        }
    }

    // On-screen volume overlay (one per screen), shown when the user adjusts
    // the TeamSpeak volume via wheel / drag on the pill or the popout row.
    Variants {
        model: Quickshell.screens
        delegate: TS6VolumeOSD {
            service: root.ts6Service
        }
    }
}
