import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "ts6status"

    // DMS 1.6+ loads translations/<locale>.json for plugins. The English
    // source string is the fallback on older DMS versions.
    function tr(term) {
        if (typeof I18n.trFor === "function")
            return I18n.trFor("ts6status", term, "ts6status");
        return I18n.tr(term);
    }

    StyledText {
        width: parent.width
        text: root.tr("TS6 Monitor Settings")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.tr("This plugin reads the TeamSpeak 6 client state through the Remote Apps API (WebSocket). On first connect, approve this app in TS6: Settings → Remote Apps → Permission Requests; the API key is saved automatically.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.Wrap
    }

    StringSetting {
        settingKey: "host"
        label: root.tr("Host")
        description: root.tr("Host where the TeamSpeak Remote Apps port listens (default 127.0.0.1)")
        placeholder: "127.0.0.1"
        defaultValue: "127.0.0.1"
    }

    StringSetting {
        settingKey: "port"
        label: root.tr("Port")
        description: root.tr("TeamSpeak Remote Apps WebSocket port (default 5899)")
        placeholder: "5899"
        defaultValue: "5899"
    }

    StyledText {
        width: parent.width
        text: root.tr("Button controls (virtual keys)")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StyledText {
        width: parent.width
        text: root.tr("The three pill buttons (microphone / speaker / away) send virtual key presses to TS6, so they work even when the TeamSpeak window is not focused. TeamSpeak currently cannot record shortcuts natively under Wayland, so launch it in X11 mode (append --ozone-platform=x11 to the command line). Then open TeamSpeak → Settings → Key Bindings and add bindings: choose \"Toggle Microphone\" and click the mic button on the pill while recording; choose \"Toggle Speaker/Mute\" and click the speaker button; choose \"Toggle Away\" and click the away button. The identifiers below are the virtual key IDs and can be changed; pressing Away also mutes the microphone.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.Wrap
    }

    StringSetting {
        settingKey: "micKey"
        label: root.tr("Microphone key identifier")
        description: root.tr("Virtual key ID bound to TS6 \"Toggle Microphone\"")
        placeholder: "dms.ts6.mic"
        defaultValue: "dms.ts6.mic"
    }

    StringSetting {
        settingKey: "muteKey"
        label: root.tr("Speaker key identifier")
        description: root.tr("Virtual key ID bound to TS6 \"Toggle Speaker/Mute\"")
        placeholder: "dms.ts6.mute"
        defaultValue: "dms.ts6.mute"
    }

    StringSetting {
        settingKey: "leaveKey"
        label: root.tr("Away key identifier")
        description: root.tr("Virtual key ID bound to TS6 \"Toggle Away\"")
        placeholder: "dms.ts6.leave"
        defaultValue: "dms.ts6.leave"
    }

    StyledText {
        width: parent.width
        text: root.tr("Display options")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    ToggleSetting {
        settingKey: "showAvatars"
        label: root.tr("Show avatars")
        description: root.tr("Show avatars in the member list")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showVolume"
        label: root.tr("Show volume")
        description: root.tr("Show per-member volume (read-only)")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showServerName"
        label: root.tr("Show server name")
        description: root.tr("Show the server name in the panel")
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showCurrentChannel"
        label: root.tr("Show current channel")
        description: root.tr("Show the current channel name in the panel")
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showChannelCount"
        label: root.tr("Show member count")
        description: root.tr("Show the channel member count in the panel")
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "debugLog"
        label: root.tr("Debug log")
        description: root.tr("Write diagnostics to debug.log in the plugin directory (off by default)")
        defaultValue: false
    }
}
