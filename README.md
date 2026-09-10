# TS6 Monitor

> 简体中文 | [English](./README.en.md)

![TS6 Monitor 截图](./screenshots/ts.png)

基于 [TeamSpeak 6](https://www.teamspeak.com/zh-CN/) **Remote Apps API**（WebSocket）的语音状态监控插件，用于 [DankMaterialShell](https://danklinux.com)（DMS）——面向 [niri](https://github.com/YaLTeR/niri)（Wayland）的 Material Design 桌面外壳。插件读取 TS6 客户端状态，实时显示在系统栏的胶囊上，并可直接在胶囊上操作语音开关。

## 特性

- **胶囊实时状态**
  - 当前频道成员头像堆叠（带说话光环）
  - 麦克风 / 扬声器 / 离开状态
  - 离开时胶囊按钮上显示离开留言文字
  - 每个成员的静音 / 闭麦角标、离开置灰
- **一键开关**（发送虚拟按键，无需聚焦窗口）
  - 切换麦克风
  - 切换扬声器 / 静音
  - 切换离开（同时关闭麦克风）
- **音量控制** —— 在胶囊 / 弹窗上拖动或滚动调整 TeamSpeak 整体音量（PipeWire），带屏幕中央 OSD 反馈
- **弹窗面板**
  - 服务器 / 频道 / 人数信息行（可开关）
  - 成员列表：头像、昵称、说话 / 静音 / 离开状态
  - 每个成员的只读音量条；自己的音量可调
- **中英双语界面** —— 在设置中即时切换，胶囊、弹窗、设置页同步生效
- 未连接或未进入频道时胶囊自动隐藏

## 环境要求

- DankMaterialShell（DMS）>= 1.4.0
- TeamSpeak 6 客户端，并启用 **Remote Apps**
- Linux（已在 CachyOS / niri / Wayland 上使用）

## 安装

1. 将本仓库克隆或下载到 DMS 的用户插件目录：
   ```bash
   mkdir -p ~/.config/DankMaterialShell/plugins
   git clone https://github.com/lemonmon/dms-plugin-TS6Monitor ~/.config/DankMaterialShell/plugins/TS6Status
   ```
2. 重启 DMS（或重载插件）。
3. 在 **DMS 设置 → 插件** 中启用，选择横向或纵向胶囊变体。

## 首次授权

1. 确认 TeamSpeak 6 已运行并启用 **Remote Apps**（设置 → Remote Apps）。
2. 插件默认连接 Remote Apps WebSocket（`ws://127.0.0.1:5899`）。
3. 在 **TeamSpeak → 设置 → Remote Apps → 权限请求** 中批准本应用，API Key 会自动保存。
4. 进入频道后胶囊即会显示。

## 配置按键

胶囊上的三个按钮通过向 TS6 发送**虚拟按键**实现，因此即使 TeamSpeak 窗口未聚焦也能生效。Wayland 下 TS6 无法原生录制快捷键，请以 X11 模式启动：

```
你的TS6启动命令 --ozone-platform=x11
```

然后打开 **TeamSpeak → 设置 → 按键绑定**，新增绑定：

| 动作             | 录制时在胶囊上点击 |
|------------------|--------------------|
| 切换麦克风       | 麦克风按钮         |
| 切换扬声器/静音  | 扬声器按钮         |
| 切换离开状态     | 离开按钮           |

虚拟按键标识符默认为 `dms.ts6.mic`、`dms.ts6.mute`、`dms.ts6.leave`，可在插件设置中修改。

## 设置选项

| 选项 | 说明 |
|------|------|
| 语言 / Language | 在中文与英文之间即时切换界面 |
| 主机 / 端口 | Remote Apps WebSocket 地址（默认 `127.0.0.1:5899`） |
| 麦克风/扬声器/离开按键标识符 | 胶囊按钮对应的虚拟按键 ID |
| 显示头像 / 音量 / 服务器 / 频道 / 人数 | 开关对应界面元素 |

## 使用技巧

- 在胶囊上滚动，或在弹窗内拖动音量条，即可调整 TeamSpeak 整体音量，OSD 会显示当前数值。
- 离开状态下，离开按钮会显示你的离开留言文字。
- 弹窗头部有刷新按钮，可重新获取头像与昵称缓存。

## 安全说明

- 插件通过 WebSocket 与 TeamSpeak 的 Remote Apps API 通信，默认使用本地回环地址 `ws://127.0.0.1:5899`（明文，仅本机）。
- 请勿修改"主机"设置为远程地址，或通过防火墙把 Remote Apps 端口暴露到不受信任的网络；如需无法连接请保持本机回环。
- `apiKey.txt` 中保存的授权密钥仅存放在你的插件目录（`.gitignore` 已排除），请勿提交或分享。

## 兼容性

- 在 DMS 1.x + niri（Wayland）+ PulseAudio/PipeWire 环境下开发与测试。
- 若系统栏为竖排，请使用纵向胶囊变体。

## 开源协议

MIT —— 见 [LICENSE](./LICENSE)。