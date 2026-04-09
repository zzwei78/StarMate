# StarMate iOS 项目架构说明

## 一、项目概述
**天通卫星电话 iOS 客户端**，通过蓝牙连接设备，实现卫星通话、短信、设备管理等功能。

---

## 二、整体架构（分层设计）

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer (Views)                      │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────────┐                  │
│  │ Home │ │Dialer│ │ SMS  │ │ Settings │                  │
│  └──────┘ └──────┘ └──────┘ └──────────┘                  │
└─────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│                      ViewModel Layer                         │
│  ┌─────────────────┐  ┌──────────────────┐                │
│  │ SettingsViewModel│  │   (其他ViewModel) │                │
│  └─────────────────┘  └──────────────────┘                │
└─────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│                   Service Layer (Managers)                   │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐   │
│  │ CallManager  │ │ AudioPipeline│ │ SatellitePhone   │   │
│  │    Impl      │ │   Manager    │ │   ManagerImpl    │   │
│  └──────────────┘ └──────────────┘ └──────────────────┘   │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐   │
│  │ BleManager   │ │ CallRecorder │   SMSManager       │   │
│  │    Impl      │ │    Impl      │                    │   │
│  └──────────────┘ └──────────────┘ └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│                    Client Layer (GATT)                       │
│  ┌──────────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │ VoiceService     │ │ ATService    │ │SystemService │   │
│  │   ClientImpl     │ │  ClientImpl  │ │  ClientImpl  │   │
│  └──────────────────┘ └──────────────┘ └──────────────┘   │
└─────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│                      Codec / Domain Layer                    │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │ AmrNbCodec   │ │AudioResampler│ │  Protocols   │       │
│  │ (编解码)      │ │  (重采样)    │ │  / Models    │       │
│  └──────────────┘ └──────────────┘ └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│                      Hardware Layer                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           CoreBluetooth / opencore-amrnb            │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、目录结构

```
StarMate/
├── Views/                    # UI 视图
│   ├── Home/                # 首页
│   ├── Dialer/              # 拨号盘
│   ├── SMS/                 # 短信
│   ├── Settings/            # 设置
│   └── Utilities/           # 工具页面
├── ViewModels/              # 视图模型
│   └── SettingsViewModel.swift
├── Data/
│   ├── Services/            # 服务实现
│   │   ├── CallManagerImpl.swift
│   │   ├── AudioPipelineManager.swift
│   │   ├── BleManagerImpl.swift
│   │   ├── VoiceServiceClientImpl.swift
│   │   ├── AtServiceClientImpl.swift
│   │   ├── SystemServiceClientImpl.swift
│   │   ├── OtaServiceClientImpl.swift
│   │   └── SatellitePhoneManagerImpl.swift
│   └── Preferences/         # 用户偏好
│       └── RecordingPreferences.swift
├── Domain/
│   ├── Codec/               # 编解码器
│   │   ├── AmrNbCodec.swift
│   │   ├── AudioResampler.swift
│   │   └── include/         # C 头文件
│   ├── Clients/             # BLE 客户端协议
│   ├── Models/              # 数据模型
│   ├── Protocol/            # 协议定义
│   └── Protocols/           # Swift 协议
│       ├── CallManagerProtocol.swift
│       ├── AudioPipelineProtocol.swift
│       └── SatellitePhoneManagerProtocol.swift
└── opencore-amrnb.xcframework  # AMR-NB 编解码库
```

---

## 四、核心功能模块

### 1. 通话模块 (CallManager)
- **拨号/接听/挂断**：通过 AT 命令 (`ATD`, `ATA`, `AT+CHUP`)
- **DTMF**：发送按键音
- **扬声器/静音**：音频模式控制
- **通话记录**：管理历史通话

### 2. 音频流水线 (AudioPipeline)
```
上行 (录音 → 发送):
麦克风 → AVAudioEngine → AudioResampler → AmrNbEncoder
      → BLE (VOICE_IN) → 设备

下行 (接收 → 播放):
设备 → BLE (VOICE_OUT) → AmrNbDecoder → AVAudioPlayerNode
      → 扬声器
```

**音频参数:**
- **编码格式**: AMR-NB MR122 (12.2 kbps)
- **采样率**: 8kHz
- **位深**: 16-bit
- **声道**: 单声道 (Mono)
- **帧大小**: 320 bytes PCM → 32 bytes AMR (20ms)
- **压缩比**: 10:1

### 3. 短信模块 (SMS)
- 发送/接收短信
- AT 命令交互

### 4. 设备管理
- 设备信息查询
- 模块状态监控
- OTA 固件升级
- 录音偏好设置

---

## 五、数据流详解

### 通话建立流程
```
makeCall()
  → ensureVoiceService()        // 确保语音服务可用
  → ATD                          // 发送拨号命令
  → startAudioPipeline()         // 启动音频流水线
  → callState = .connected       // 更新状态为已连接
```

### AMR 语音数据传输

#### 上行 (录音 → 设备)
```
AudioPipelineManager
  → AVAudioEngine 采集音频 (44.1kHz Float32)
  → AudioResampler 重采样到 8kHz Int16
  → PcmFrameBuffer 分帧 (320 bytes/帧)
  → AmrNbEncoder 编码 (32 bytes/帧)
  → Delegate 回调
  → CallManagerImpl
  → VoiceServiceClientImpl
  → 包装为 AT^AUDPCM="<base64>"
  → BLE VOICE_IN 特征值
  → 设备
```

#### 下行 (设备 → 播放)
```
设备
  → BLE VOICE_OUT 特征值
  → VoiceServiceClientImpl
  → 解析 AT^AUDPCM 命令
  → Base64 解码
  → CallManagerImpl.feedDownlinkAmr()
  → AudioPipelineManager
  → AmrNbDecoder 解码 (320 bytes/帧)
  → AVAudioPlayerNode 播放
```

### BLE GATT 服务

#### Voice Service (UUID: 0xABF0)
| 特征值 | 方向 | 用途 |
|--------|------|------|
| VOICE_IN | 写 | 发送 AMR 数据到设备 |
| VOICE_OUT | 通知/读 | 接收设备的 AMR 数据 |

#### AT Service
| 特征值 | 方向 | 用途 |
|--------|------|------|
| AT_TX | 写 | 发送 AT 命令 |
| AT_RX | 通知/读 | 接收 AT 响应和 URC |

#### System Service
| 特征值 | 方向 | 用途 |
|--------|------|------|
| CMD | 写 | 系统命令 |
| DATA | 通知/读 | 系统数据 |

---

## 六、关键协议

### BLE 服务 UUID
```swift
// TTCat Service UUID
serviceUUID: 0000FFF0-0000-1000-8000-00805F9B34FB

// Characteristics
deviceInfo:     0000FFF1-...
batteryStatus:  0000FFF2-...
signalStatus:   0000FFF3-...
moduleStatus:   0000FFF4-...
networkStatus:  0000FFF5-...
command:        0000FFF6-...
```

### AT^AUDPCM 协议格式
```
AT^AUDPCM="<base64_encoded_amr_data>"

示例:
AT^AUDPCM="BpcQIw==..."  // 32 bytes AMR 的 Base64 编码
```

---

## 七、技术栈

| 层级 | 技术 |
|------|------|
| UI | SwiftUI |
| 蓝牙 | CoreBluetooth (BLE GATT) |
| 音频 | AVFoundation |
| 编解码 | opencore-amrnb (C库 + Swift封装) |
| 并发 | async/await, Combine |
| 数据存储 | UserDefaults (RecordingPreferences) |

---

## 八、AMR-NB 编解码

### 模式选择
当前使用 **MR122 (12.2 kbps)** 模式，提供最佳音质。

### 支持的模式
| 模式 | 比特率 | 帧大小 |
|------|--------|--------|
| MR475 | 4.75 kbps | - |
| MR515 | 5.15 kbps | - |
| MR59 | 5.90 kbps | - |
| MR67 | 6.70 kbps | - |
| MR74 | 7.40 kbps | - |
| MR795 | 7.95 kbps | - |
| MR102 | 10.2 kbps | - |
| **MR122** | **12.2 kbps** | **32 bytes** |
| MRDTX | DTX | - |

### 文件格式
```
#!AMR\n
<帧1><帧2><帧3>...

每帧格式:
[TOC byte][AMR data...]
- TOC byte: 编码模式 + 帧类型
- AMR data: 压缩的语音数据
```

---

## 九、测试功能

SettingsViewModel 中包含临时测试功能:
- **测试录音**: 录音 → AMR-NB 编码 → 保存为 .amr 文件
- **测试播放**: 读取 .amr → AMR-NB 解码 → 播放

测试文件保存位置: `~/AudioTest/*.amr`

---

*最后更新: 2026-04-09*
