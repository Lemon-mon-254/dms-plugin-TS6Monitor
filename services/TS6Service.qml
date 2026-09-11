pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtWebSockets
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root

    // Runtime paths, resolved from the user's real config/cache locations so
    // the plugin works for any user (FileView writes proved unreliable in the
    // plugin sub-instance, so we shell out via Process).
    readonly property string _home: Paths.strip(Paths.home)
    readonly property string _base: Paths.strip(Paths.config) + "/plugins/TS6Status"
    readonly property string apiKeyPath: root._base + "/apiKey.txt"
    readonly property string debugPath: root._base + "/debug.log"
    readonly property string avatarCachePath: root._base + "/avatarCache.json"
    readonly property string avatarLocalDir: root._home + "/.cache/ts6avatar"

    // File mirror for the debug ring below; enable in the plugin settings.
    property bool debugLog: false

    // Persistent cache of long-lived/nearly-invariant per-user data, keyed by the
    // member's stable databaseId (legacyUUID is only exposed for self/connection
    // info, not for plain clients). Stored so a restart keeps avatars + names
    // without re-fetching. Values: { nick, avatar }.
    property var _avatarCache: ({})
    property bool _avatarCacheLoaded: false
    property string _lastCacheRead: ""

    property string _lastRead: ""

    // Async, declared Process instances (quickshell's Process has no exec(); use
    // `running` to trigger). Avoids the Qt.createQmlObject() recursion issue.
    function _fileWrite(path, content) {
        _writeProc.command = ["/bin/sh", "-c", "printf %s \"$1\" > \"$2\"", "sh", content, path];
        _writeProc.running = true;
    }

    function _fileAppend(path, content) {
        _appendProc.command = ["/bin/sh", "-c", "printf '%s\\n' \"$1\" >> \"$2\"", "sh", content, path];
        _appendProc.running = true;
    }

    function _fileRead(path) {
        root._lastRead = "";
        _readProc.command = ["/bin/sh", "-c", "cat \"$1\" 2>/dev/null", "sh", path];
        _readProc.running = true;
    }

    Process {
        id: _writeProc
        onExited: (exitCode, exitStatus) => { _writeProc.running = false; }
    }
    Process {
        id: _appendProc
        onExited: (exitCode, exitStatus) => { _appendProc.running = false; }
    }
    property string _flushBuf: ""
    Timer {
        interval: 400
        running: root._flushBuf !== ""
        repeat: true
        onTriggered: root._flushDebug()
    }
    function _flushDebug() {
        if (_flushBuf === "") return;
        if (_appendProc.running) return;
        const buf = _flushBuf;
        _flushBuf = "";
        _fileAppend(debugPath, buf.replace(/\n$/, ""));
    }
    Process {
        id: _readProc
        stdout: StdioCollector {
            id: _readCollector
            waitForEnd: true
            onStreamFinished: { root._lastRead = _readCollector.text || ""; }
        }
        onExited: (exitCode, exitStatus) => {
            _readProc.running = false;
            const k = root._lastRead.trim();
            if (k !== "")
                root.pluginSettingsApiKey = k;
        }
    }

    Process {
        id: _cacheReadProc
        stdout: StdioCollector {
            id: _cacheReadCollector
            waitForEnd: true
            onStreamFinished: { root._lastCacheRead = _cacheReadCollector.text || ""; }
        }
        onExited: (exitCode, exitStatus) => {
            _cacheReadProc.running = false;
            root._loadCacheFromString(root._lastCacheRead);
        }
    }

    // Downloads/re-downloads an avatar URL to a local file so that delegates can
    // load from disk (near-instant) instead of re-fetching from the network on
    // every delegate rebuild (which caused the dark flicker while talking).
    Process {
        id: _avatarDl
        stdout: StdioCollector { id: _avatarDlCol; waitForEnd: true }
        onExited: (exitCode, exitStatus) => {
            _avatarDl.running = false;
            const key = root._downloadPendingKey;
            const url = root._downloadPendingUrl;
            root._downloadPendingKey = "";
            root._downloadPendingUrl = "";
            if (key !== "" && url !== "") {
                const entry = root._avatarCache[key];
                if (entry) {
                    entry.local = root._avatarLocalPath(key);
                    entry.downloaded = true;
                    root._saveCache();
                    root.debugLog("[AVD] downloaded " + key + " -> " + entry.local + " (code " + exitCode + ")");
                    root._notify();
                }
            }
            root._avatarDlNextPending();
        }
    }
    property string _downloadPendingKey: ""
    property string _downloadPendingUrl: ""

    function _avatarLocalPath(key) {
        return avatarLocalDir + "/" + root._hashStr(key) + ".png";
    }
    function _hashStr(s) {
        let h = 5381;
        for (let i = 0; i < s.length; i++) {
            h = ((h * 33) ^ s.charCodeAt(i)) >>> 0;
        }
        return h.toString(36);
    }
    // Start the next pending download (serial queue, one curl at a time).
    function _avatarDlNextPending() {
        if (_avatarDl.running) return;
        for (const key in root._avatarCache) {
            const e = root._avatarCache[key];
            if (!e || !e.avatar) continue;
            const url = e.avatar;
            if (!(url.startsWith("http://") || url.startsWith("https://"))) continue;
            if (e.downloaded) continue;
            root._downloadPendingKey = key;
            root._downloadPendingUrl = url;
            const local = root._avatarLocalPath(key);
            e.local = local;
            e.downloaded = false;
            _avatarDl.command = ["/bin/sh", "-c", "mkdir -p \"$1\" && curl -sfL --max-time 20 -o \"$2\" \"$3\"", "sh", avatarLocalDir, local, url];
            _avatarDl.running = true;
            return;
        }
    }
    // Schedule downloads for any cached avatars not yet local (idempotent).
    function _downloadAvatar(key, entry) {
        if (!entry) return;
        const url = entry.avatar;
        if (!url || !(url.startsWith("http://") || url.startsWith("https://"))) return;
        if (entry.downloaded) return;
        root._avatarDlNextPending();
    }

    // --- avatar/nickname cache (persisted across restarts) ---
    function _loadCacheFromString(s) {
        const text = (s || "").trim();
        let obj = {};
        if (text !== "") {
            try { obj = JSON.parse(text); } catch (e) { obj = {}; }
        }
        root._avatarCache = (obj && typeof obj === "object") ? obj : {};
        root._avatarCacheLoaded = true;
        root.debugLog("[CACHE] loaded " + Object.keys(root._avatarCache).length + " entries");
        for (const k in root._avatarCache) {
            const e = root._avatarCache[k];
            root.debugLog("[CACHE] " + k + " local=" + (e && e.local) + " dl=" + (e && e.downloaded) + " av=" + (e && e.avatar ? "y" : "n"));
        }
        root._notify();
    }

    function _saveCache() {
        if (avatarCachePath === "") return;
        root._fileWrite(avatarCachePath, JSON.stringify(root._avatarCache));
    }

    // Stable cache key: prefer databaseId (permanent per server), else clientId.
    function _cacheKeyFor(p, clientId) {
        if (p && p.databaseId !== undefined && p.databaseId !== null && p.databaseId !== "")
            return "db:" + String(p.databaseId);
        return "id:" + clientId;
    }

    // Lazily (re)fill one cache entry from a client's live properties. Idempotent:
    // if the key already exists we do nothing, so unrelated events (talking etc.)
    // never trigger a re-parse / re-download. Only a missing key (new member) or an
    // explicit refreshCache() re-extracts the avatar/name.
    function _fillCacheFor(client, conn) {
        if (!client) return;
        const p = client.properties || {};
        const key = root._cacheKeyFor(p, client.id);
        if (!root._avatarCacheLoaded) return;
        if (key in root._avatarCache) return;

        const entry = {
            nick: root.clientDisplayName(client),
            avatar: root.avatarUrl(client)
        };
        root._avatarCache[key] = entry;
        root._saveCache();
        root.debugLog("[CACHE] fill " + key + " nick='" + entry.nick + "' avatar=" + (entry.avatar ? "yes" : "no"));
        root._downloadAvatar(key, entry);
    }

    // Read cached values for display (fill on first use).
    function cachedNick(client, conn) {
        if (!client) return "";
        const p = client.properties || {};
        const key = root._cacheKeyFor(p, client.id);
        root._fillCacheFor(client, conn);
        const e = root._avatarCache[key];
        return e ? (e.nick || "") : "";
    }

    function cachedAvatar(client, conn) {
        if (!client) return "";
        const p = client.properties || {};
        const key = root._cacheKeyFor(p, client.id);
        root._fillCacheFor(client, conn);
        const e = root._avatarCache[key];
        if (!e) return "";
        // Prefer an already-downloaded local file (loads faster on rebuild).
        if (e.downloaded && e.local && e.local !== "") return "file://" + e.local;
        root._downloadAvatar(key, e);
        return e.avatar || "";
    }

    // Force re-extraction of every cache entry from current live client data.
    function refreshCache() {
        root._avatarCache = {};
        root._avatarCacheLoaded = true;
        const conns = root.connections;
        for (const perConn of conns) {
            if (perConn && perConn.clients) {
                for (const clKey in perConn.clients) {
                    root._fillCacheFor(perConn.clients[clKey], perConn);
                }
            }
        }
        root.debugLog("[CACHE] refreshed");
    }

    // =============================================================
    // TeamSpeak (PipeWire) overall output volume control
    // =============================================================
    // The overall TS output volume is a PipeWire sink-input owned by the
    // TeamSpeak client. We locate it by application.name and read/set its
    // volume via pactl (pactl ships with PipeWire everywhere).
    property real tsVolume01: -1   // 0..1, -1 = unknown
    readonly property bool tsVolumeKnown: root.tsVolume01 >= 0

    property string _tsVolStr: ""
    Process {
        id: _tsVolRead
        stdout: StdioCollector {
            id: _tsVolReadCol
            waitForEnd: true
            onStreamFinished: {
                root._tsVolStr = _tsVolReadCol.text || "";
                const m = root._tsVolStr.match(/id=\d+ vol=(\d+)/);
                if (m) root.tsVolume01 = parseInt(m[1], 10) / 100;
                else root.tsVolume01 = -1;
            }
        }
        onExited: () => {
            _tsVolRead.running = false;
        }
    }
    Process {
        id: _tsVolSet
        onExited: (exitCode, exitStatus) => { _tsVolSet.running = false; }
    }

    function refreshTsVolume() {
        if (_tsVolRead.running) return;
        root._tsVolStr = "";
        _tsVolRead.command = ["/bin/sh", "-c",
            "pactl list sink-inputs | awk '/Sink Input #[0-9]+/{id=substr($3,2);vol=\"\"} /Volume: front-left:/{for(i=1;i<=NF;i++) if($i ~ /%$/){gsub(/[^0-9]/,\"\",$i);vol=$i}} /application.name = \"TeamSpeak\"/{print \"id=\" id \" vol=\" vol; exit}'",
            "sh"];
        _tsVolRead.running = true;
    }

    function setTsVolume01(v) {
        v = Math.max(0, Math.min(1, v));
        root.tsVolume01 = Math.round(v * 100) / 100;
        root.volumeUserChanged(root.tsVolume01);
        if (_tsVolSet.running) return;
        _tsVolSet.command = ["/bin/sh", "-c",
            "p=$(pactl list sink-inputs | awk '/Sink Input #[0-9]+/{id=substr($3,2)} /application.name = \"TeamSpeak\"/{print id; exit}') && [ -n \"$p\" ] && pactl set-sink-input-volume \"$p\" " + Math.round(v*100) + "% || true",
            "sh"];
        _tsVolSet.running = true;
    }
    signal volumeUserChanged(real v)

    // Keep the displayed TS volume fresh while connected.
    Timer {
        id: tsVolRefresh
        interval: 3000
        repeat: true
        running: root.connected
        onTriggered: root.refreshTsVolume()
    }
    onConnectedChanged: { if (root.connected) root.refreshTsVolume(); }

    // Keep a small ring of debug lines and mirror them to a file so we can
    // inspect the live auth/socket flow (plugin console.log is not captured in
    // quickshell's log.log).
    property var _dbgLines: []

    function debugLog(msg) {
        console.log("[TS6Service] " + msg);
        if (!root.debugLog) return;
        const line = new Date().toTimeString().slice(0, 8) + "  " + msg;
        _dbgLines.push(line);
        if (_dbgLines.length > 200) _dbgLines = _dbgLines.slice(-200);
        if (debugPath !== "" && _flushBuf.length < 60000) _flushBuf += line + "\n";
    }

    // ---- Connection prefs (bound from widget settings) ----
    property string serverHost: "127.0.0.1"
    property int serverPort: 5899

    // ---- Remote App identity ----
    // Fixed lowercase identifier. The first connection must be approved in
    // TeamSpeak (Settings -> Remote Apps), after which the client returns an
    // apiKey that we persist and reuse.
    readonly property string appIdentifier: "com.dms.tsMonitor"
    readonly property string appName: "TS6 Monitor"
    readonly property string appDescription: "DankMaterialShell TeamSpeak 6 status monitor"

    // ---- WebSocket state ----
    property bool connected: false
    property bool authenticated: false
    property bool pendingAuth: false          // true while waiting for user to approve in TS6
    property string lastError: ""

    // ---- Ingested model ----
    // connections: array of {
    //   id, clientId, name, properties,
    //   channels: { id: {id,parentId,order,name,topic} },
    //   clients: { clientId: {id, talkStatus, channelId, properties} }
    // }
    property var connections: []

    // Monotonic counter bumped on every data change; used to force QML binding
    // re-evaluation that relies on mutation of nested objects inside `connections`.
    property int notifyTick: 0

    // Which connection is the "active" one (the one the UI focuses on)
    property int activeConnectionId: -1

    // ---- Derived convenience state (bound to active connection) ----
    readonly property bool hasActiveConnection: activeConnectionId >= 0 && getConnection(activeConnectionId) !== undefined
    readonly property string serverName: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        if (!c) return "";
        return c.name || c.properties?.virtualserver_name || (c.properties && c.properties.hasOwnProperty("nickname") && c.clientId >= 0 ? c.properties.nickname : "") || "";
    }
    readonly property string selfNickname: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        const self = c && c.clients ? c.clients[c.clientId] : undefined;
        return self ? (self.properties.nickname || "") : "";
    }
    readonly property var selfClient: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        return c && c.clients ? c.clients[c.clientId] : undefined;
    }
    readonly property string selfAvatarUrl: {
        const s = root.selfClient;
        return s ? avatarUrl(s) : "";
    }
    // Channel containing ourselves
    readonly property int selfChannelId: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        const self = c && c.clients ? c.clients[c.clientId] : undefined;
        return self ? self.channelId : -1;
    }
    readonly property string channelName: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        if (!c || selfChannelId < 0) return "";
        const ch = c.channels ? c.channels[selfChannelId] : undefined;
        return ch ? ch.name : "";
    }
    readonly property bool selfInputMuted_: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        const self = c && c.clients ? c.clients[c.clientId] : undefined;
        return self ? !!self.properties.inputMuted : false;
    }
    readonly property bool selfOutputMuted: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        const self = c && c.clients ? c.clients[c.clientId] : undefined;
        return self ? !!self.properties.outputMuted : false;
    }
    readonly property bool selfInputMuted: root.selfInputMuted_
    readonly property bool selfAway: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        const self = c && c.clients ? c.clients[c.clientId] : undefined;
        return self ? !!self.properties.away : false;
    }
    readonly property string selfAwayMessage: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        const self = c && c.clients ? c.clients[c.clientId] : undefined;
        const m = self && self.properties ? self.properties.awayMessage : "";
        return (m && String(m).trim() !== "") ? String(m).trim() : "";
    }
    readonly property bool selfTalking: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        const self = c && c.clients ? c.clients[c.clientId] : undefined;
        return self ? (self.talkStatus === 1 || self.talkStatus === 3) : false;
    }

    readonly property int channelClientCount: root.channelClients.length

    // Stable pill avatar model. Unlike channelClients (which returns a fresh
    // array + fresh decorated objects on every notify, forcing the Repeater to
    // destroy/recreate delegates and reload avatar images -> flicker while
    // talking), this ListModel is updated IN PLACE via set()/append()/remove().
    // Clients in our current channel. The TS6 Remote Apps API is a client-side
    // view, so every reported client is a real user in a channel (no server
    // query). We therefore do NOT filter out `type === 1` clients, since the
    // local user (type 1) must be included too.
    readonly property var channelClients: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        if (!c || !c.clients) return [];
        const list = [];
        for (const key in c.clients) {
            const cl = c.clients[key];
            if (root._sameChannel(cl.channelId, root.selfChannelId) && cl.properties) {
                list.push(_decorateClient(cl, c));
            }
        }
        // Keep ourselves pinned at the front of the pill/list.
        const selfId = root.activeSelfId();
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === selfId) {
                if (i !== 0) {
                    const self = list.splice(i, 1)[0];
                    list.unshift(self);
                }
                break;
            }
        }
        return list;
    }

    // Clients currently talking (across the whole active server), for the pill/badge
    readonly property var talkingClients: {
        root.notifyTick;
        const c = getConnection(activeConnectionId);
        if (!c || !c.clients) return [];
        const list = [];
        for (const key in c.clients) {
            const cl = c.clients[key];
            if (cl.properties && (cl.talkStatus === 1 || cl.talkStatus === 3 || cl.properties.flagTalking === true)) {
                list.push(_decorateClient(cl, c));
            }
        }
        return list;
    }
    readonly property int talkingCount: root.talkingClients.length

    readonly property bool configMissing: false

    // =========================================================
    // Helper
    // =========================================================
    function getConnection(connId) {
        for (let i = 0; i < root.connections.length; i++) {
            if (root.connections[i].id === connId) return root.connections[i];
        }
        return undefined;
    }

    function clientDisplayName(cl) {
        const p = cl && cl.properties ? cl.properties : {};
        return (p.nickname || p.name || p.clientNickName || p.clientNickname || p.displayName || "Unknown user");
    }

    function _decorateClient(cl, conn) {
        const p = cl && cl.properties ? cl.properties : {};
        root._fillCacheFor(cl, conn);
        return {
            id: cl.id,
            talkStatus: cl.talkStatus,
            channelId: cl.channelId,
            properties: p,
            displayName: root.clientDisplayName(cl),
            avatarUrl: root.avatarUrl(cl),
            connectionId: conn ? conn.id : -1,
            // Note: decorate with a stable identity so re-render doesn't lose state
        };
    }

    // Avatar URL resolution. The only publicly loadable source exposed by the
    // Remote Apps API is the MyTeamSpeak avatar (myteamspeakAvatar). Its value is
    // NOT a single URL — it is a semicolon-separated list of "<size>,<url>"
    // entries, one per resolution bucket (e.g.
    // "1,https://.../1558425820;2,https://.../398550116;..."). We parse it and
    // pick the URL of the largest available size. flagAvatar is an MD5 hash that
    // only flags the presence of a server-side avatar; the pixel data lives on
    // the TeamSpeak server and is NOT exposed by the Remote Apps API, so no
    // external URL can be fabricated from it (a bogus fallback 404'd). We return
    // "" so the UI falls back to the person icon.
    function avatarUrl(client) {
        if (!client) return "";
        const p = client.properties || client;
        const raw = (
            p.myteamspeakAvatar ??
            p.myTeamSpeakAvatar ??
            p.myteamspeakavatar ??
            p.myTeamspeakAvatar ??
            p.mytsAvatar ??
            p.avatarUrl ??
            p.avatarURL ??
            p.avatar ??
            p.myteamspeakAvatarUrl ??
            p.myTeamSpeakAvatarUrl
        );
        if (raw === null || raw === undefined || raw === "") return "";

        const parts = String(raw).split(";");
        let best = "";
        let bestSize = -1;
        for (const part of parts) {
            const piece = String(part).trim();
            if (piece === "") continue;
            const comma = piece.indexOf(",");
            let url = piece;
            let size = -1;
            if (comma > 0) {
                url = piece.slice(comma + 1).trim();
                const n = parseInt(piece.slice(0, comma).trim(), 10);
                size = isNaN(n) ? -1 : n;
            }
            if (url && (url.startsWith("http://") || url.startsWith("https://"))) {
                if (size > bestSize) {
                    bestSize = size;
                    best = url;
                }
            }
        }
        if (best !== "") return best;
        for (const part of parts) {
            const piece = String(part).trim();
            if (piece === "") continue;
            const idx = piece.indexOf(",");
            const u = (idx > 0 ? piece.slice(idx + 1) : piece).trim();
            if (u.startsWith("http://") || u.startsWith("https://")) return u;
        }
        return "";
    }

    // Id of ourselves within the active connection (-1 if unknown)
    function activeSelfId() {
        const c = getConnection(activeConnectionId);
        return c ? c.clientId : -1;
    }

    // Force a full re-poll: reconnect the WS (re-triggers auth + connection data)
    function forceRefresh() {
        root.reconnect();
    }

    // Force a reconnect of the WebSocket (used when host/port/auth changes)
    function reconnect() {
        socket.active = false;
        socket.active = true;
    }

    // =========================================================
    // Key / button triggering (for bound hotkeys)
    // =========================================================
    function sendKeyPress(button, down) {
        if (socket.active && socket.status === WebSocket.Open) {
            socket.sendTextMessage(JSON.stringify({
                type: "buttonPress",
                payload: { button: button, state: down }
            }));
        }
    }
    // Press then release (discrete click) - for mic/mute toggle
    function triggerButton(button) {
        sendKeyPress(button, true);
        _releaseTimer.button = button;
        _releaseTimer.restart();
    }

    Timer {
        id: _releaseTimer
        interval: 120
        property string button: ""
        onTriggered: {
            if (_releaseTimer.button !== "")
                root.sendKeyPress(_releaseTimer.button, false);
            _releaseTimer.button = "";
        }
    }

    // =========================================================
    // WebSocket
    // =========================================================
    WebSocket {
        id: socket
        active: true
        url: "ws://" + root.serverHost + ":" + root.serverPort

        onStatusChanged: {
            root.lastError = "";
            root.debugLog("STATUS -> " + socket.status);
            if (socket.status === WebSocket.Open) {
                root.connected = true;
                root.pendingAuth = false;
                _sendAuth();
            } else if (socket.status === WebSocket.Closed || socket.status === WebSocket.Error) {
                root.connected = false;
                root.authenticated = false;
            }
        }

        onErrorStringChanged: {
            root.lastError = socket.errorString;
        }

        onTextMessageReceived: message => {
            let data;
            try {
                data = JSON.parse(message);
            } catch (e) {
                return;
            }
            if (data.type !== "auth") {
                root.debugLog("EVENT " + data.type + " " + JSON.stringify(data.payload || {}).slice(0, 400));
            }
            switch (data.type) {
                case "auth": _handleAuth(data); break;
                case "clientMoved": _handleClientMoved(data); break;
                case "clientPropertiesUpdated": _handleClientPropertiesUpdated(data); break;
                case "talkStatusChanged": _handleTalkStatusChanged(data); break;
                case "clientSelfPropertyUpdated": _handleClientSelfPropertyUpdated(data); break;
                case "serverPropertiesUpdated": _handleServerPropertiesUpdated(data); break;
                case "connectStatusChanged": _handleConnectStatusChanged(data); break;
                case "channels": _handleChannels(data); break;
                case "channelCreated": _handleChannelCreated(data); break;
                case "channelRemoved": _handleChannelRemoved(data); break;
                case "channelMoved": _handleChannelMoved(data); break;
                case "channelPropertiesUpdated": _handleChannelPropertiesUpdated(data); break;
                // "channels", "clientChannelGroupChanged", "chatMessage", "permissionList" etc.
                default: break;
            }
        }
    }

    // Reconnect with simple exponential backoff while not connected
    Timer {
        id: reconnectTimer
        interval: 3000
        repeat: true
        running: !root.connected
        onTriggered: {
            if (!root.connected) {
                socket.active = false;
                socket.active = true;
            }
        }
    }

    // Re-send auth periodically while connected but not yet authenticated.
    // This gives the user a fresh TS6 approval prompt if the first one was
    // missed, and lets us pick up the apiKey once approved. Kept slow so we
    // don't flood TeamSpeak with simultaneous approval requests.
    Timer {
        id: authRetryTimer
        interval: 15000
        repeat: true
        running: root.connected && !root.authenticated
        onTriggered: {
            root.debugLog("re-sending auth (auth=" + root.authenticated + " pending=" + root.pendingAuth + ")");
            _sendAuth();
        }
    }

    function _sendAuth() {
        const key = pluginSettingsApiKey;
        socket.sendTextMessage(JSON.stringify({
            type: "auth",
            payload: {
                identifier: root.appIdentifier,
                version: "1.0.0",
                name: root.appName,
                description: root.appDescription,
                content: { apiKey: key }
            }
        }));
        root.pendingAuth = key === "";
    }

    // store api key between restarts
    property string pluginSettingsApiKey: ""

    function _safeStr(o) {
        try {
            return String(JSON.stringify(o));
        } catch (e) {
            return "{" + Object.keys(o).join(",") + ":<unserializable>}";
        }
    }

    function _handleAuth(data) {
        const authConns = (data.payload && data.payload.connections) || [];
        root.debugLog("AUTH payload connections=[" + authConns.length + "]");
        if (data.status && data.status.code === 0) {
            root.authenticated = true;
            root.pendingAuth = false;
            const key = data.payload && data.payload.apiKey ? data.payload.apiKey : "";
            if (key !== "" && key !== root.pluginSettingsApiKey) {
                root.pluginSettingsApiKey = key;
                _saveApiKey(key);
                if (root.pluginServiceSave) root.pluginServiceSave(key);
            }
            // Reset and (re)populate model
            root.connections = [];
            if (authConns.length > 0) {
                authConns.forEach(connPayload => {
                    try {
                        const conn = _makeConnection(connPayload);
                        root.connections.push(conn);
                        if (root.activeConnectionId < 0) root.activeConnectionId = conn.id;
                        _populateConnection(conn, connPayload);
                        root.debugLog("CONN " + conn.id + " name='" + conn.name + "' clientId=" + conn.clientId
                            + " channels=" + Object.keys(conn.channels).length
                            + " clients=" + Object.keys(conn.clients).length);
                    } catch (e) {
                        root.debugLog("AUTH conn ERR " + e);
                    }
                });
                root.connections = root.connections.slice();
            }
            root.debugLog("POST-AUTH active=" + root.activeConnectionId
                + " selfChannel=" + root.selfChannelId
                + " channelClients=" + root.channelClients.length
                + " talking=" + root.talkingCount);
        } else if (data.status && data.status.code !== 0) {
            root.lastError = (data.status.message || "Auth failed") + (data.status.code ? (" (" + data.status.code + ")") : "");
            root.authenticated = false;
        }
    }

    // Build a connection skeleton from the auth payload connection object
    function _makeConnection(payload) {
        return {
            id: payload.id,
            clientId: payload.clientId,
            name: payload.properties ? (payload.properties.virtualserver_name || payload.properties.name || "") : "",
            properties: payload.properties || {},
            channels: {},
            clients: {}
        };
    }

    function _normChan(v) {
        if (v === null || v === undefined) return 0;
        const n = parseInt(String(v).trim(), 10);
        return isNaN(n) ? 0 : n;
    }

    function _mergeObject(dst, src) {
        const target = dst || {};
        const incoming = src || {};
        for (const key in incoming) {
            if (Object.prototype.hasOwnProperty.call(incoming, key)) {
                target[key] = incoming[key];
            }
        }
        return target;
    }

    function _populateConnection(conn, payload) {
        // Channels from channelInfos
        try {
            if (payload.channelInfos) {
                if (payload.channelInfos.rootChannels) {
                    payload.channelInfos.rootChannels.forEach(ch => {
                        conn.channels[ch.id] = _makeChannel(ch, conn.id);
                    });
                }
                if (payload.channelInfos.subChannels) {
                    for (const parentKey in payload.channelInfos.subChannels) {
                        payload.channelInfos.subChannels[parentKey].forEach(ch => {
                            conn.channels[ch.id] = _makeChannel(ch, conn.id);
                        });
                    }
                }
            }
        } catch (e) { root.debugLog("POP channel ERR " + e); }
        // Clients from clientInfos
        try {
            if (payload.clientInfos) {
                payload.clientInfos.forEach(ci => {
                    conn.clients[ci.id] = {
                        id: ci.id,
                        talkStatus: 0,
                        channelId: root._normChan(ci.channelId),
                        properties: ci.properties || {}
                    };
                });
            }
        } catch (e) { root.debugLog("POP client ERR " + e); }
        if (payload.clients) {
            for (const clKey in payload.clients) {
                const cl = payload.clients[clKey];
                conn.clients[cl.id !== undefined ? cl.id : parseInt(clKey)] = {
                    id: cl.id !== undefined ? cl.id : parseInt(clKey),
                    talkStatus: 0,
                    channelId: root._normChan(cl.channelId !== undefined ? cl.channelId : cl.channel),
                    properties: cl.properties || {}
                };
            }
        }
    }

    function _makeChannel(ch, connId) {
        return {
            id: ch.id,
            connectionId: connId,
            parentId: ch.parentId !== undefined ? ch.parentId : (ch.parent ? ch.parent : ""),
            order: ch.order || "",
            name: ch.properties ? (ch.properties.name || "") : "",
            topic: ch.properties ? (ch.properties.topic || "") : "",
            properties: ch.properties || {}
        };
    }

    function _sameChannel(a, b) {
        return root._normChan(a) === root._normChan(b);
    }

    function _notify() {
        // force re-evaluation of derived arrays by touching the connections array
        root.connections = root.connections.slice();
        root.notifyTick++;
    }

    function _handleConnectStatusChanged(data) {
        const connId = data.payload.connectionId;
        const status = data.payload.status;
        if (status === 0) {
            // disconnected - remove connection
            root.connections = root.connections.filter(c => c.id !== connId);
            if (root.activeConnectionId === connId) {
                root.activeConnectionId = root.connections.length ? root.connections[0].id : -1;
            }
        } else if (status === 4) {
            // connected - add skeleton, populated by subsequent channels/clientMoved events
            let conn = root.getConnection(connId);
            if (!conn) {
                conn = { id: connId, clientId: data.payload.info ? data.payload.info.clientId : -1, name: "", properties: {}, channels: {}, clients: {} };
                root.connections.push(conn);
                root.activeConnectionId = connId;
            }
        }
        _notify();
    }

    function _handleServerPropertiesUpdated(data) {
        const conn = root.getConnection(data.payload.connectionId);
        if (conn) {
            conn.properties = data.payload.properties;
            conn.name = data.payload.properties.virtualserver_name || data.payload.properties.name || conn.name;
            _notify();
        }
    }

    function _handleClientSelfPropertyUpdated(data) {
        const connId = data.payload.connectionId;
        // Heuristic: the connection this event belongs to is the one with focus
        root.activeConnectionId = connId;
        const flag = data.payload.flag;
        const conn = root.getConnection(connId);
            if (conn && conn.clients && conn.clientId >= 0 && conn.clients[conn.clientId]) {
                const self = conn.clients[conn.clientId];
                self.properties = self.properties || {};
                if (flag !== undefined && data.payload.newValue !== undefined) {
                    self.properties[flag] = data.payload.newValue;
                }
                root.debugLog("SELF flag=" + flag + " away=" + self.properties.away + " inputMuted=" + self.properties.inputMuted + " outputMuted=" + self.properties.outputMuted);
                _notify();
            }
    }

    function _handleClientPropertiesUpdated(data) {
        const conn = root.getConnection(data.payload.connectionId);
        if (conn && conn.clients && conn.clients[data.payload.clientId]) {
            const client = conn.clients[data.payload.clientId];
            client.properties = root._mergeObject(client.properties || {}, data.payload.properties || {});
            if (data.payload.clientId === conn.clientId) root.debugLog("CLIENTPROPS self=" + JSON.stringify(data.payload.properties || {}));
            _notify();
        }
    }

    function _handleTalkStatusChanged(data) {
        const conn = root.getConnection(data.payload.connectionId);
        if (conn && conn.clients && conn.clients[data.payload.clientId]) {
            conn.clients[data.payload.clientId].talkStatus = data.payload.status;
            _notify();
        }
    }

    function _handleClientMoved(data) {
        const conn = root.getConnection(data.payload.connectionId);
        if (!conn) return;
        const clientId = data.payload.clientId;
        const oldChan = root._normChan(data.payload.oldChannelId);
        const newChan = root._normChan(data.payload.newChannelId);
        const incomingProps = data.payload.properties || {};



        if (oldChan === 0) {
            // joined server / new client; keep any existing state if the event is
            // repeated or partial, but always update the current channel and props.
            const existing = conn.clients[clientId];
            if (existing) {
                existing.channelId = newChan;
                existing.properties = root._mergeObject(existing.properties || {}, incomingProps);
                existing.talkStatus = existing.talkStatus || 0;
            } else {
                conn.clients[clientId] = {
                    id: clientId,
                    talkStatus: 0,
                    channelId: newChan,
                    properties: root._mergeObject({}, incomingProps)
                };
            }
            _notify();
            return;
        }

        const existing = conn.clients[clientId];
        if (existing) {
            existing.channelId = newChan;
            existing.properties = root._mergeObject(existing.properties || {}, incomingProps);
        } else {
            conn.clients[clientId] = {
                id: clientId,
                talkStatus: 0,
                channelId: newChan,
                properties: root._mergeObject({}, incomingProps)
            };
        }
        _notify();
    }

    function _handleChannels(data) {
        const conn = root.getConnection(data.payload.connectionId);
        if (!conn) return;
        const info = data.payload.info;
        if (info) {
            if (info.rootChannels) {
                info.rootChannels.forEach(ch => { conn.channels[ch.id] = _makeChannel(ch, conn.id); });
            }
            if (info.subChannels) {
                for (const key in info.subChannels) {
                    info.subChannels[key].forEach(ch => { conn.channels[ch.id] = _makeChannel(ch, conn.id); });
                }
            }
        }
        _notify();
    }

    function _handleChannelCreated(data) {
        const conn = root.getConnection(data.payload.connectionId);
        if (conn) {
            conn.channels[data.payload.channelId] = {
                id: data.payload.channelId,
                connectionId: data.payload.connectionId,
                parentId: data.payload.parentId !== undefined ? data.payload.parentId : "",
                order: data.payload.properties ? data.payload.properties.order || "" : "",
                name: data.payload.properties ? data.payload.properties.name || "" : "",
                topic: data.payload.properties ? data.payload.properties.topic || "" : "",
                properties: data.payload.properties || {}
            };
            _notify();
        }
    }

    function _handleChannelRemoved(data) {
        const conn = root.getConnection(data.payload.connectionId);
        if (conn && conn.channels && data.payload.channelId !== undefined) {
            delete conn.channels[data.payload.channelId];
            // any clients in that channel get cleared
            for (const key in conn.clients) {
                if (conn.clients[key].channelId === data.payload.channelId) {
                    delete conn.clients[key];
                }
            }
            _notify();
        }
    }

    function _handleChannelMoved(data) {
        const conn = root.getConnection(data.payload.connectionId);
        if (conn && conn.channels && conn.channels[data.payload.channelId]) {
            const ch = conn.channels[data.payload.channelId];
            ch.parentId = data.payload.newParent !== undefined ? data.payload.newParent : ch.parentId;
            if (data.payload.properties && data.payload.properties.order !== undefined) ch.order = data.payload.properties.order;
            _notify();
        }
    }

    function _handleChannelPropertiesUpdated(data) {
        const conn = root.getConnection(data.payload.connectionId);
        if (conn && conn.channels && conn.channels[data.payload.channelId]) {
            const ch = conn.channels[data.payload.channelId];
            ch.properties = data.payload.properties || ch.properties;
            if (data.payload.properties && data.payload.properties.name !== undefined) ch.name = data.payload.properties.name;
            if (data.payload.properties && data.payload.properties.topic !== undefined) ch.topic = data.payload.properties.topic;
            _notify();
        }
    }

    // ---- apiKey persistence (own file, not tied to DMS pluginService) ----
    // The first connection must be approved in TS6 (Settings -> Remote Apps);
    // the returned apiKey is stored to disk so restarts don't re-prompt.

    function _loadApiKey() {
        // Async read; pluginSettingsApiKey is assigned in _readProc.onExited once
        // the file content is available.
        _fileRead(apiKeyPath);
    }

    function _saveApiKey(key) {
        if (!key || key === "") return;
        if (apiKeyPath === "") return;
        _fileWrite(apiKeyPath, key);
    }

    Component.onCompleted: {
        _loadApiKey();
        _cacheReadProc.command = ["/bin/sh", "-c", "cat \"$1\" 2>/dev/null", "sh", avatarCachePath];
        _cacheReadProc.running = true;
    }

    // Kept for compatibility; the widget no longer relies on it.
    property var pluginServiceSave: null
}
