# StarMate iOS App

天通卫星通信终端 iOS 应用

## 项目概述

StarMate 是一款用于管理 TTCat 天通卫星通信终端的 iOS 应用，采用 Swift 和 SwiftUI 开发。

## 功能特性

### 🏠 主页 (Home)
- BLE 设备扫描与连接管理
- 实时设备状态监控
- 电池电量、电压、电流显示
- 卫星模块状态、信号强度、网络状态

### 📞 拨号器 (Dialer)
- 电话拨号键盘
- 通话管理（拨打、接听、挂断）
- 通话记录
- 通话中控制（扬声器、静音）

### 💬 短信 (SMS)
- 会话列表
- 聊天界面
- 发送/接收短信
- 未读消息提示

### ⚙️ 设置 (Settings)
- 充电管理（无线充电、Boost输出）
- 通话录音设置
- 设备管理（重启控制）
- 终端信息显示
- 基带信息
- OTA 固件升级

## 系统要求

- iOS 17.0+
- Xcode 15.0+
- macOS Sonoma (14.0)+
- iPhone with Bluetooth LE

## 构建和运行

### 方式一：直接在 Mac 上构建

1. **克隆项目**
   ```bash
   git clone <repository-url>
   cd StarMate
   ```

2. **打开项目**
   ```bash
   open StarMate.xcodeproj
   ```

3. **选择目标设备**
   - 在 Xcode 顶部工具栏选择 iPhone 模拟器或真机

4. **运行**
   - 按 `⌘R` 或点击播放按钮

### 方式二：使用 GitHub Actions（无需 Mac）

1. 推送代码到 GitHub
2. Actions 会自动在 macOS runner 上构建
3. 下载构建产物

### 方式三：命令行构建

```bash
# 列出可用模拟器
xcrun simctl list devices

# 构建
xcodebuild build \
  -project StarMate.xcodeproj \
  -scheme StarMate \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# 运行测试
xcodebuild test \
  -project StarMate.xcodeproj \
  -scheme StarMate \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## 项目结构

```
StarMate/
├── StarMateApp.swift           # App 入口
├── ContentView.swift           # 主 TabView
├── Info.plist                  # 应用配置
├── StarMateApp.entitlements    # 权限配置
│
├── Assets.xcassets/            # 资源文件
│   ├── AppIcon.appiconset/     # App 图标
│   ├── AccentColor.colorset/   # 主题色
│   ├── LaunchScreen.imageset/  # 启动图
│   └── LaunchBackground.colorset/
│
├── Base.lproj/
│   └── LaunchScreen.storyboard # 启动屏幕
│
├── Theme/
│   ├── ColorScheme.swift       # 颜色定义
│   └── AppTheme.swift          # 主题常量
│
├── Models/
│   ├── DeviceModels.swift      # 设备模型
│   ├── CallModels.swift        # 通话模型
│   ├── SMSModels.swift         # 短信模型
│   └── OTAModels.swift         # OTA 模型
│
├── Services/
│   ├── BLEManager.swift        # 蓝牙管理
│   ├── CallManager.swift       # 通话管理
│   └── SMSManager.swift        # 短信管理
│
├── Views/
│   ├── Home/
│   │   └── HomeView.swift      # 主页
│   ├── Dialer/
│   │   └── DialerView.swift    # 拨号器
│   ├── SMS/
│   │   └── SMSView.swift       # 短信
│   ├── Settings/
│   │   └── SettingsView.swift  # 设置
│   └── Utilities/
│       ├── LaunchScreenView.swift
│       └── IconGeneratorView.swift
│
└── .github/workflows/
    └── build.yml               # CI/CD 配置
```

## 权限说明

| 权限 | 用途 |
|------|------|
| Bluetooth | 连接 TTCat 卫星终端 |
| Microphone | 通话录音（可选） |

## 设计风格

- iOS 原生设计语言
- 系统蓝 (#007AFF) 主色调
- 圆角卡片布局
- 支持深色模式

## 从 Android 版本移植

本项目基于 CosmoCat Android 应用移植，保持功能一致：

| Android (Kotlin) | iOS (Swift) |
|------------------|-------------|
| Jetpack Compose | SwiftUI |
| Hilt/Dagger | @EnvironmentObject |
| StateFlow | @Published |
| Room | UserDefaults |
| BLE GATT | CoreBluetooth |

## 开发团队

StarMate © 2024

## License

Copyright © 2024 StarMate. All rights reserved.
