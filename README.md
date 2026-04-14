# LiveDashBoardAgent

LiveDashBoardAgent 是一个运行在 macOS 菜单栏中的轻量状态上报代理。

应用以 `MenuBarExtra` 形式常驻菜单栏，周期性采集当前前台应用、窗口标题、空闲状态、电池信息和音乐播放信息，并将数据发送到服务端。项目同时内置权限检测、配置编辑、关键词脱敏和可选文件日志，适合用于工作状态采集、桌面活跃度记录或轻量运维看板接入场景。

# 需要注意：CI构建的安装包实测安装后存在无法授权辅助功能权限的问题，请克隆项目后自行在本机用XCode打包安装

## 功能概览

- 菜单栏常驻，点击后弹出状态面板
- 状态总览页实时展示运行状态、最近上报时间、当前前台应用、空闲时长、电池和音乐信息
- 权限页检测辅助功能权限，并可直接触发系统授权提示
- 配置页支持编辑服务端地址、Token、轮询间隔、心跳间隔、AFK 阈值、日志开关和关键词过滤规则
- 自动识别 AFK 状态，并在合适时机上报 `idle`
- 对前台应用名、窗口标题和音乐元数据做关键词脱敏
- 可选文件日志，按天滚动并自动清理过期日志

## 运行要求

- macOS 13.0 及以上
- 一套支持 macOS 13 SDK 的 Xcode 环境
- 为了读取当前窗口标题，需要授予“辅助功能”权限
- 如需读取部分音乐 App 的播放信息，系统可能会弹出自动化相关授权提示

## 快速开始

1. 使用 Xcode 打开 [LiveDashBoardAgent.xcodeproj](/Users/steve5wutongyu6/Documents/xcode/LiveDashBoardAgent/LiveDashBoardAgent.xcodeproj)。
2. 选择 Scheme `LiveDashBoardAgent`。
3. 运行后，应用会以状态圆点的形式出现在 macOS 菜单栏中。
4. 打开菜单栏面板，在“权限”页授予辅助功能权限。
5. 在“配置”页填入服务端地址和 Token，保存后即可开始监控和上报。

## 界面说明

应用面板包含 3 个标签页：

- `状态`：展示生命周期、最近一次成功上报时间、当前应用、空闲时长、电池、音乐、窗口标题、配置路径、权限状态和退避等待时间
- `权限`：展示辅助功能权限状态，并在缺失时引导用户授权
- `配置`：编辑全部运行参数，并支持保存、从磁盘重载、放弃未保存修改、打开配置目录

## 配置文件

应用启动时会按以下优先级查找 `config.json`：

1. 应用包同级目录下的 `config.json`
2. 当前工作目录下的 `config.json`
3. `~/Library/Application Support/LiveDashBoardAgent/config.json`

如果上述位置都不存在配置文件，应用会以默认配置启动，并在首次保存时写入第 3 个位置。

### 配置示例

```json
{
  "serverURLString": "https://your-server.example.com",
  "token": "YOUR_TOKEN_HERE",
  "intervalSeconds": 5,
  "heartbeatSeconds": 60,
  "idleThresholdSeconds": 300,
  "enableLog": false,
  "keywordFilterText": "客户A|项目代号|秘密关键字"
}
```

### 字段说明

- `serverURLString`：服务端基础地址。应用会自动向 `{serverURLString}/api/report` 发送上报请求
- `token`：Bearer Token，不能为空，也不能保留为占位值 `YOUR_TOKEN_HERE`
- `intervalSeconds`：轮询间隔，允许范围 `1...300`
- `heartbeatSeconds`：心跳上报间隔，允许范围 `10...600`
- `idleThresholdSeconds`：AFK 判定阈值，允许范围 `30...3600`
- `enableLog`：是否开启文件日志
- `keywordFilterText`：关键词过滤规则，多个关键词使用 `|` 分隔，保存前会自动去空白、去空项和去重

### 配置校验规则

- 仅支持 `http` 或 `https`
- 对公网主机要求使用 `https`
- `http` 仅适用于 `localhost`、`.local` 或常见内网地址

## 上报行为

### 触发时机

- 当前前台应用或窗口标题发生变化时立即上报
- 距离上一次成功上报超过 `heartbeatSeconds` 时触发心跳上报
- 用户进入 AFK 状态后，会按心跳规则继续上报空闲状态

### AFK 判定

满足以下条件时视为 AFK：

- 空闲时间大于等于 `idleThresholdSeconds`
- 当前没有活跃音频输出
- 当前窗口不是全屏状态

AFK 上报时会发送：

- `app_id = "idle"`
- `window_title = "User is away"`

### 请求信息

- 方法：`POST`
- 路径：`{serverURLString}/api/report`
- Header：`Authorization: Bearer <token>`
- Header：`Content-Type: application/json`

请求体结构如下：

```json
{
  "app_id": "Xcode",
  "window_title": "LiveDashBoardAgent.xcodeproj",
  "timestamp": 1712920000000,
  "extra": {
    "battery_percent": 82,
    "battery_charging": true,
    "music": {
      "app": "Spotify",
      "title": "Song Title",
      "artist": "Artist Name"
    }
  }
}
```

### 成功与失败策略

- 返回 `200`、`201`、`409` 视为成功
- 失败后会进行指数退避，起始 5 秒，最大 60 秒
- 连续失败 5 次后会进入 300 秒保护性暂停，然后重置失败计数

## 数据采集范围

当前实现会采集以下信息：

- 前台应用名
- 当前聚焦窗口标题
- 空闲时长
- 电池电量和充电状态
- 音频播放豁免状态
- 音乐播放信息

支持识别的音乐应用包括：

- Spotify
- Music
- QQ音乐
- 网易云音乐

其中，音乐信息读取使用 AppleScript 实现；若目标应用未运行、未播放或未授权，相关字段会为空。

## 脱敏规则

关键词过滤由 `keywordFilterText` 控制，多个关键词使用 `|` 分隔。

命中关键词后，以下字段中的匹配内容会被替换为 `***`：

- 前台应用名
- 窗口标题
- 音乐应用名
- 歌曲标题
- 歌手名

关键词匹配默认忽略大小写，且会优先匹配更长的关键词。

## 日志与工作目录

默认工作目录：

```text
~/Library/Application Support/LiveDashBoardAgent/
```

文件日志开启后，会写入：

```text
~/Library/Application Support/LiveDashBoardAgent/Logs/
```

日志特性：

- 使用 `OSLog` 输出结构化日志
- 可选按天写入 `agent-YYYY-MM-DD.log`
- 自动清理 2 天前的旧日志

## 项目结构

```text
LiveDashBoardAgent/
├── LiveDashBoardAgentApp.swift          # 应用入口，挂载菜单栏窗口
├── ContentView.swift                    # 菜单栏主面板
├── Models/
│   ├── AgentConfiguration.swift         # 配置模型与校验逻辑
│   └── AgentRuntimeState.swift          # 运行态模型
├── ViewModels/
│   └── AgentDashboardStore.swift        # SwiftUI 状态管理与动作分发
├── Services/
│   ├── AgentCoordinator.swift           # 监控循环与上报编排
│   ├── ConfigurationStore.swift         # 配置文件读写
│   ├── ForegroundWorkspaceService.swift # 前台窗口与权限检测
│   ├── SystemEnvironmentService.swift   # Idle、电池、音频状态
│   ├── AppleScriptMusicService.swift    # 音乐信息检测
│   ├── NetworkReporter.swift            # HTTP 上报与失败退避
│   ├── ReportKeywordRedactor.swift      # 关键词脱敏
│   └── AppLogger.swift                  # 结构化日志
└── Views/                               # 状态、权限、配置等面板组件
```

## 常见问题

### 看不到窗口标题

通常是因为辅助功能权限未授权。请打开应用面板中的“权限”页，触发系统授权提示，然后在系统设置中允许本应用访问辅助功能。

### 配置一直无法保存

请优先检查以下内容：

- `serverURLString` 是否为空
- `token` 是否仍是占位值
- 服务端地址是否缺少协议头
- 公网地址是否错误地使用了 `http`

### 音乐信息为空

可能原因包括：

- 当前没有支持的音乐应用在播放
- 目标应用未运行
- AppleScript 调用未获得对应自动化授权

### 上报失败后长时间没有恢复

应用在连续失败 5 次后会暂停 300 秒，这是保护性退避行为。可以优先检查：

- 服务端地址是否正确
- `/api/report` 接口是否可用
- Token 是否有效
- 本机网络是否正常

## 开发说明

- 当前工程没有引入第三方依赖，主要使用 `SwiftUI`、`AppKit`、`Foundation`、`IOKit` 和 `ApplicationServices`
- 应用状态管理集中在 `AgentDashboardStore`
- 监控逻辑集中在 `AgentCoordinator`
- UI 与配置、上报、权限检测等逻辑已经按模块拆分，后续扩展可以优先沿用现有目录结构

