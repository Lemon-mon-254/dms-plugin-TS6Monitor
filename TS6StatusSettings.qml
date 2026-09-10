import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "ts6status"

    property string _lang: "zh"
    readonly property var _zh: ({
        "settingsTitle": "TS6 Monitor 设置",
        "intro": "本插件通过 TeamSpeak 6 的 Remote Apps API（WebSocket）读取客户端状态。首次连接时请在 TS6：设置 → Remote Apps → 权限请求 中批准本应用，API Key 会自动保存。",
        "languageLabel": "语言",
        "languageDesc": "界面显示语言，切换后即时生效",
        "optionZh": "中文",
        "optionEn": "English",
        "hostLabel": "主机",
        "hostDesc": "TeamSpeak 远程应用端口所在主机（默认 127.0.0.1）",
        "portLabel": "端口",
        "portDesc": "TeamSpeak Remote Apps WebSocket 端口（默认 5899）",
        "keySection": "开关控制（发送虚拟按键）",
        "keyIntro": "胶囊上三个按钮（麦克风/扬声器/离开）通过向 TS6 发送“虚拟按键”实现，不受窗口聚焦限制。请先用 X11 模式启动 TeamSpeak（启动命令加 --ozone-platform=x11，否则 Wayland 下 TS6 无法录入快捷键），然后：打开 TeamSpeak → 设置 → 按键绑定，新增绑定：动作选“切换麦克风”→ 录制时点击胶囊的麦克风按钮；动作选“切换扬声器/静音”→ 点击扬声器按钮；动作选“离开（切换离开状态）”→ 点击离开按钮。下面的标识符是这些虚拟键的 ID，可自行修改；点离开发送离开键的同时也会关闭麦克风。",
        "micKeyLabel": "麦克风按键标识符",
        "micKeyDesc": "绑定到 TS6“切换麦克风”的虚拟按键 ID",
        "muteKeyLabel": "扬声器按键标识符",
        "muteKeyDesc": "绑定到 TS6“切换扬声器/静音”的虚拟按键 ID",
        "leaveKeyLabel": "离开按键标识符",
        "leaveKeyDesc": "绑定到 TS6“切换离开状态”的虚拟按键 ID",
        "displaySection": "显示选项",
        "showAvatarsLabel": "显示头像",
        "showAvatarsDesc": "在成员列表中显示头像",
        "showVolumeLabel": "显示音量",
        "showVolumeDesc": "显示每个成员的音量（只读）",
        "showServerNameLabel": "显示服务器名称",
        "showServerNameDesc": "在面板中显示服务器名称",
        "showCurrentChannelLabel": "显示当前频道",
        "showCurrentChannelDesc": "在面板中显示当前频道名称",
        "showChannelCountLabel": "显示频道人数",
        "showChannelCountDesc": "在面板中显示频道成员人数",
        "debugLogLabel": "调试日志",
        "debugLogDesc": "将诊断信息写入插件目录下的 debug.log（默认关闭）"
    })
    readonly property var _en: ({
        "settingsTitle": "TS6 Monitor Settings",
        "intro": "This plugin reads the TeamSpeak 6 client state through the Remote Apps API (WebSocket). On first connect, approve this app in TS6: Settings → Remote Apps → Permission Requests; the API key is saved automatically.",
        "languageLabel": "Language",
        "languageDesc": "Interface language; changes apply immediately",
        "optionZh": "Chinese",
        "optionEn": "English",
        "hostLabel": "Host",
        "hostDesc": "Host where the TeamSpeak Remote Apps port listens (default 127.0.0.1)",
        "portLabel": "Port",
        "portDesc": "TeamSpeak Remote Apps WebSocket port (default 5899)",
        "keySection": "Button controls (virtual keys)",
        "keyIntro": "The three pill buttons (microphone / speaker / away) work by sending “virtual key presses” to TS6, unaffected by window focus. First launch TeamSpeak in X11 mode (append --ozone-platform=x11 to the command line, otherwise TS6 cannot record shortcuts under Wayland). Then open TeamSpeak → Settings → Key Bindings and add bindings: pick action “Toggle Microphone” → while recording click the mic button on the pill; pick “Toggle Speaker/Mute” → click the speaker button; pick “Toggle Away” → click the away button. The identifiers below are the virtual key IDs and can be changed freely; pressing away also mutes the microphone.",
        "micKeyLabel": "Microphone key identifier",
        "micKeyDesc": "Virtual key ID bound to TS6 \"Toggle Microphone\"",
        "muteKeyLabel": "Speaker key identifier",
        "muteKeyDesc": "Virtual key ID bound to TS6 \"Toggle Speaker/Mute\"",
        "leaveKeyLabel": "Away key identifier",
        "leaveKeyDesc": "Virtual key ID bound to TS6 \"Toggle Away\"",
        "displaySection": "Display options",
        "showAvatarsLabel": "Show avatars",
        "showAvatarsDesc": "Show avatars in the member list",
        "showVolumeLabel": "Show volume",
        "showVolumeDesc": "Show per-member volume (read-only)",
        "showServerNameLabel": "Show server name",
        "showServerNameDesc": "Show the server name in the panel",
        "showCurrentChannelLabel": "Show current channel",
        "showCurrentChannelDesc": "Show the current channel name in the panel",
        "showChannelCountLabel": "Show member count",
        "showChannelCountDesc": "Show the channel member count in the panel",
        "debugLogLabel": "Debug log",
        "debugLogDesc": "Write diagnostics to debug.log in the plugin directory (off by default)"
    })
    readonly property var _dict: root._lang === "en" ? root._en : root._zh
    function t(key) { return root._dict[key] !== undefined ? root._dict[key] : key }

    StyledText {
        width: parent.width
        text: root.t("settingsTitle")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    SelectionSetting {
        id: langSetting
        settingKey: "language"
        label: root.t("languageLabel")
        description: root.t("languageDesc")
        options: [
            { value: "zh", label: root.t("optionZh") },
            { value: "en", label: root.t("optionEn") }
        ]
        defaultValue: "zh"
    }

    Connections {
        target: langSetting
        function onValueChanged() {
            root._lang = langSetting.value;
        }
    }

    StyledText {
        width: parent.width
        text: root.t("intro")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.Wrap
    }

    StringSetting {
        settingKey: "host"
        label: root.t("hostLabel")
        description: root.t("hostDesc")
        placeholder: "127.0.0.1"
        defaultValue: "127.0.0.1"
    }

    StringSetting {
        settingKey: "port"
        label: root.t("portLabel")
        description: root.t("portDesc")
        placeholder: "5899"
        defaultValue: "5899"
    }

    StyledText {
        width: parent.width
        text: root.t("keySection")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StyledText {
        width: parent.width
        text: root.t("keyIntro")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.Wrap
    }

    StringSetting {
        settingKey: "micKey"
        label: root.t("micKeyLabel")
        description: root.t("micKeyDesc")
        placeholder: "dms.ts6.mic"
        defaultValue: "dms.ts6.mic"
    }

    StringSetting {
        settingKey: "muteKey"
        label: root.t("muteKeyLabel")
        description: root.t("muteKeyDesc")
        placeholder: "dms.ts6.mute"
        defaultValue: "dms.ts6.mute"
    }

    StringSetting {
        settingKey: "leaveKey"
        label: root.t("leaveKeyLabel")
        description: root.t("leaveKeyDesc")
        placeholder: "dms.ts6.leave"
        defaultValue: "dms.ts6.leave"
    }

    StyledText {
        width: parent.width
        text: root.t("displaySection")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    ToggleSetting {
        settingKey: "showAvatars"
        label: root.t("showAvatarsLabel")
        description: root.t("showAvatarsDesc")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showVolume"
        label: root.t("showVolumeLabel")
        description: root.t("showVolumeDesc")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showServerName"
        label: root.t("showServerNameLabel")
        description: root.t("showServerNameDesc")
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showCurrentChannel"
        label: root.t("showCurrentChannelLabel")
        description: root.t("showCurrentChannelDesc")
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showChannelCount"
        label: root.t("showChannelCountLabel")
        description: root.t("showChannelCountDesc")
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "debugLog"
        label: root.t("debugLogLabel")
        description: root.t("debugLogDesc")
        defaultValue: false
    }
}