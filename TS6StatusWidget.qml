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

    // Pill visibility driven directly via setVisibilityOverride (so the async
    // visibilityCommand process can't clamp conditionVisible back to false).
    Connections {
        target: svc
        function onConnectedChanged() {
            root.setVisibilityOverride(root.showWhenConnected);
        }
        function onNotifyTickChanged() {
            root.setVisibilityOverride(root.showWhenConnected);
        }
        function onHasActiveConnectionChanged() {
            root.setVisibilityOverride(root.showWhenConnected);
        }
        function onSelfChannelIdChanged() {
            root.setVisibilityOverride(root.showWhenConnected);
        }
    }
    Connections {
        target: root
        function onShowWhenConnectedChanged() {
            root.setVisibilityOverride(root.showWhenConnected);
        }
    }
    Component.onCompleted: root.setVisibilityOverride(root.showWhenConnected)

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
    readonly property bool debugEnabled: pluginData.debugEnabled === true || pluginData.debugLog === true

    // Members hidden from the bar pills. Stored as an array of stable client
    // keys ("db:<databaseId>" when available, otherwise "id:<clientId>") so the
    // choice survives nick/avatar changes. The member list in the popout still
    // shows them; only the pill avatars are filtered.
    readonly property var hiddenPillIds: {
        var raw = pluginData.hiddenPillIds !== undefined ? pluginData.hiddenPillIds : []
        if (Array.isArray(raw))
            return raw.map(function (v) { return String(v) })
        if (typeof raw !== "string" || raw.trim() === "")
            return []
        try {
            var parsed = JSON.parse(raw)
            if (Array.isArray(parsed))
                return parsed.map(function (v) { return String(v) })
        } catch (e) {}
        return raw.split(",").map(function (v) { return v.trim() }).filter(function (v) { return v !== "" })
    }

    function _clientKey(client) {
        if (!client) return ""
        var p = client.properties || {}
        if (p.databaseId !== undefined && p.databaseId !== null && p.databaseId !== "")
            return "db:" + String(p.databaseId)
        return client.id !== undefined && client.id >= 0 ? "id:" + String(client.id) : ""
    }

    function isPillHidden(client) {
        var key = root._clientKey(client)
        return key !== "" && root.hiddenPillIds.indexOf(key) >= 0
    }

    function togglePillHidden(client, show) {
        var key = root._clientKey(client)
        if (key === "") return
        var next = root.hiddenPillIds.filter(function (v) { return v !== key })
        if (!show)
            next.push(key)
        try {
            pluginData.hiddenPillIds = next
        } catch (e) {
            console.warn("[TS6] 无法保存胶囊头像显示设置: " + e)
        }
    }

    // Channel members shown on the pills, in the same order as the member list.
    readonly property var pillClients: {
        var list = root.ts6Service.notifyTick >= 0 ? root.ts6Service.channelClients : []
        var out = []
        for (var i = 0; i < list.length; i++) {
            if (!root.isPillHidden(list[i]))
                out.push(list[i])
        }
        return out
    }

    // Slightly larger avatar shown on the capsules, plus a speaking ring.
    readonly property real pillAvatarSize: 30

    // Width occupied by the three control buttons on the pill. The third
    // (leave) button grows when it shows the awayMessage text instead of only
    // the door icon, so we estimate its width (Chinese chars are ~11px wide).
    readonly property int _leaveBtnW: root.ts6Service.selfAway && root.ts6Service.selfAwayMessage !== ""
        ? Math.ceil(root.ts6Service.selfAwayMessage.length * 11) + Theme.spacingXS
        : 20
    readonly property real pillControlsWidth: root.showWhenConnected ? 20 + 20 + root._leaveBtnW : 0

    // True when the Remote Apps socket is up, we are connected to a server and
    // are inside a channel. This is what makes the whole pill appear/disappear
    // (empty channel still shows). Requiring `connected` makes the pill hide as
    // soon as TeamSpeak quits / the socket drops, even if the server model has
    // not been cleared yet.
    readonly property bool showWhenConnected: root.ts6Service.connected && root.ts6Service.notifyTick >= 0 && root.ts6Service.hasActiveConnection && root.ts6Service.selfChannelId > 0

    // ----- Plugin i18n (English source strings + translations/) -----
    // DMS 1.6+ loads translations/<locale>.json for plugins. Keep the fallback
    // to I18n.tr() so older DMS versions still show the English source string.
    function tr(term) {
        if (typeof I18n.trFor === "function")
            return I18n.trFor("ts6status", term, "ts6status");
        return I18n.tr(term);
    }

    // ----- The TS6 status service (one instance per widget) -----
    readonly property var ts6Service: svc
    TS6Service {
        id: svc
    }

    // ----- Forward settings into the service -----
    Binding { target: ts6Service; property: "serverHost"; value: root.hostSetting }
    Binding { target: ts6Service; property: "serverPort"; value: root.portSetting }
    Binding { target: ts6Service; property: "debugEnabled"; value: root.debugEnabled }

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
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        DankIcon {
            anchors.centerIn: parent
            name: btnRoot.icon
            size: Theme.iconSizeSmall - 1
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
            implicitHeight: root.ts6Service.notifyTick >= 0 && root.pillClients.length > 0 ? root.pillAvatarSize * root.pillClients.length + Theme.spacingXS * Math.max(0, root.pillClients.length - 1) : 0

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
                    model: root.ts6Service.notifyTick >= 0 ? root.pillClients : []
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
                                color: Theme.surfaceContainer
                            }
                            DankIcon {
                                anchors.fill: parent
                                name: modelData.properties.outputMuted ? "volume_off" : "mic_off"
                                size: Theme.iconSizeSmall - 4
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
            implicitWidth: root.showWhenConnected ? (root.pillClients.length > 0 ? root.pillAvatarSize * root.pillClients.length + Theme.spacingXS * root.pillClients.length : 0) + root.pillControlsWidth + 0 : 0
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
                        tint: (root.ts6Service.selfAway && root.ts6Service.selfOutputMuted) ? Theme.warning : Theme.surfaceText
                        highlightColor: (root.ts6Service.selfAway && root.ts6Service.selfOutputMuted) ? Theme.warning : Theme.primary
                        highlighted: root.ts6Service.selfAway
                    }
                }

                Row {
                    spacing: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: root.ts6Service.notifyTick >= 0 ? root.pillClients : []
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
                                color: Theme.surfaceContainer
                            }
                            DankIcon {
                                anchors.fill: parent
                                name: modelData.properties.outputMuted ? "volume_off" : "mic_off"
                                size: Theme.iconSizeSmall - 4
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
                ToolTip.text: root.tr("Refresh avatar & nickname cache")
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
                            if (!root.ts6Service.connected) return root.tr("Not connected to TeamSpeak (make sure TS6 is installed and Remote Apps is enabled)")
                            if (root.ts6Service.pendingAuth || !root.ts6Service.authenticated)
                                return root.tr("Approve this app in TeamSpeak → Settings → Remote Apps → Permission Requests")
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
                            text: root.tr("Server: %1").arg(root.ts6Service.serverName || "—")
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: root.showCurrentChannel
                            text: root.tr("Channel: %1").arg(root.ts6Service.channelName || "—")
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: root.showChannelCount
                            text: root.tr("Members: %1").arg(root.ts6Service.channelClientCount)
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
                                        color: Theme.surfaceContainer
                                    }
                                    DankIcon {
                                        anchors.fill: parent
                                        name: modelData.properties.outputMuted ? "volume_off" : "mic_off"
                                        size: Theme.iconSizeSmall - 2
                                        color: Theme.primary
                                    }
                                }
                            }

                            Row {
                                width: parent.width - 34 - 32 - (root.showVolume ? 150 : 0) - Theme.spacingS * (root.showVolume ? 4 : 3)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                StyledText {
                                    text: root.ts6Service.cachedNick(modelData) || modelData.displayName || modelData.properties.nickname || modelData.properties.name || root.tr("Unknown user")
                                    color: row.isSelf ? Theme.primary : Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.bold: row.isSelf
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: {
                                        if (row.isTalking) return root.tr("Talking")
                                        if (modelData.properties.inputMuted) return root.tr("Microphone muted")
                                        if (modelData.properties.outputMuted) return root.tr("Muted (can't hear)")
                                        if (modelData.properties.away) return root.tr("Away")
                                        return ""
                                    }
                                    color: row.isTalking ? Theme.success : (modelData.properties.inputMuted ? Theme.error : Theme.surfaceVariantText)
                                    font.pixelSize: Theme.fontSizeSmall
                                    visible: text !== ""
                                }
                            }

                            // 胶囊显示开关：关闭后此人不出现在栏上胶囊，成员列表照常显示
                            Rectangle {
                                id: pillToggle
                                width: 32
                                height: 32
                                radius: 16
                                anchors.verticalCenter: parent.verticalCenter
                                color: pillToggleArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                readonly property bool shown: !root.isPillHidden(modelData)

                                DankIcon {
                                    anchors.centerIn: parent
                                    name: pillToggle.shown ? "visibility" : "visibility_off"
                                    size: Theme.iconSizeSmall
                                    color: pillToggle.shown ? Theme.primary : Theme.surfaceVariantText
                                }
                                MouseArea {
                                    id: pillToggleArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.togglePillHidden(modelData, !pillToggle.shown)
                                }
                                ToolTip.visible: pillToggleArea.containsMouse
                                ToolTip.text: pillToggle.shown
                                    ? root.tr("Hide avatar on pill")
                                    : root.tr("Show avatar on pill")
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
                    DankIcon { name: "group_off"; size: Theme.iconSizeLarge + Theme.spacingXS; color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
                    StyledText { text: root.tr("Not connected"); color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
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
