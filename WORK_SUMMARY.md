# StarMate iOS 项目工作总结

## 项目概述
将 CosmoCat Android 天通卫星通信应用移植到 iOS 平台，使用 Swift + SwiftUI 开发。

## 架构设计

### 整体分层 (与 Android CosmoCat 一致)

```
┌────────────────────────────────────────────────────────────┐
│  Presentation Layer                                        │
│  Views (SwiftUI) + ViewModels (@Observable)               │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│  Domain Layer                                              │
│  Repository Interfaces + UseCases + Manager Interfaces     │
│  Domain Models (enum sealed class 风格)                    │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│  Data Layer                                                │
│  Repository Impl + Manager Impl                            │
│  BLE Clients (System/AT/Voice/OTA)                        │
│  Protocol (BleUuid, Commands, PacketBuilder, CRC)          │
│  Local Storage (Database, Preferences)                     │
└────────────────────────────────────────────────────────────┘
```

### 目录结构

```
StarMate/iOS/StarMate/
├── Domain/
│   ├── Protocol/
│   │   ├── BleUuid.swift              # BLE UUID 定义
│   │   ├── BleUuidHelper.swift        # UUID 辅助函数
│   │   ├── SystemCommands.swift       # System Service 命令码
│   │   ├── AtCommands.swift           # AT 命令常量
│   │   ├── SystemPacketBuilder.swift  # 数据包构建/解析
│   │   └── Crc16.swift                # CRC16-CCITT/MODBUS
│   │
│   ├── Models/
│   │   ├── ConnectModels.swift        # 连接状态模型
│   │   ├── DeviceModels.swift         # 设备信息模型
│   │   ├── ModuleModels.swift         # TT模块/SIM/网络状态
│   │   ├── CallModels.swift           # 通话模型
│   │   ├── SmsModels.swift            # 短信模型
│   │   ├── OtaModels.swift            # OTA 升级模型
│   │   └── AtModels.swift             # AT 响应/通知模型
│   │
│   └── Clients/
│       ├── BleManagerProtocol.swift   # BLE 管理器接口
│       └── BleServiceClients.swift    # 服务客户端接口
│
├── Data/
│   └── Services/
│       ├── BleManagerImpl.swift       # BLE 管理器实现
│       ├── SystemServiceClientImpl.swift
│       ├── AtServiceClientImpl.swift
│       ├── VoiceServiceClientImpl.swift (待实现)
│       └── OtaServiceClientImpl.swift (待实现)
│
└── Presentation/
    ├── Theme/
    ├── Views/
    └── ViewModels/
```

## 已完成工作

### 1. 协议层 (Protocol Layer) ✅

#### BLE UUID 定义
```swift
enum BleUuid {
    // Services
    static let SYSTEM_SERVICE: CBUUID = CBUUID(string: "ABFC")
    static let AT_SERVICE: CBUUID = CBUUID(string: "ABF2")
    static let VOICE_SERVICE: CBUUID = CBUUID(string: "ABF0")
    static let OTA_SERVICE: CBUUID = CBUUID(string: "ABF8")

    // System Service Characteristics
    static let SYSTEM_CONTROL: CBUUID = CBUUID(string: "ABFD")  // Write + Notify
    static let SYSTEM_INFO: CBUUID = CBUUID(string: "ABFE")     // Read (96 bytes)
    static let SYSTEM_STATUS: CBUUID = CBUUID(string: "ABFF")   // Notify

    // AT Service Characteristics
    static let AT_COMMAND: CBUUID = CBUUID(string: "ABF3")      // Write + Notify
    static let AT_RESPONSE: CBUUID = CBUUID(string: "ABF1")     // Notify

    // Voice Service Characteristics
    static let VOICE_IN: CBUUID = CBUUID(string: "ABEE")        // Write
    static let VOICE_OUT: CBUUID = CBUUID(string: "ABEF")       // Notify
    static let VOICE_DATA: CBUUID = CBUUID(string: "ABF1")      // Write + Notify

    // OTA Service Characteristics
    static let OTA_CONTROL: CBUUID = CBUUID(string: "ABF9")     // Write + Notify
    static let OTA_DATA: CBUUID = CBUUID(string: "ABFA")        // Write
    static let OTA_STATUS: CBUUID = CBUUID(string: "ABFB")      // Notify
}
```

#### System Service 命令码
```swift
enum SystemCommands {
    static let CMD_GET_BATTERY_INFO: UInt8 = 0x01
    static let CMD_GET_CHARGE_STATUS: UInt8 = 0x02
    static let CMD_GET_TT_SIGNAL: UInt8 = 0x03
    static let CMD_SERVICE_START: UInt8 = 0x10
    static let CMD_SERVICE_STOP: UInt8 = 0x11
    static let CMD_SERVICE_STATUS: UInt8 = 0x12
    static let CMD_SYSTEM_REBOOT: UInt8 = 0x20
    static let CMD_REBOOT_MCU: UInt8 = 0x22
    static let CMD_REBOOT_TT: UInt8 = 0x23
    static let CMD_GET_SYSTEM_INFO: UInt8 = 0x30
    static let CMD_GET_VERSION_INFO: UInt8 = 0x31
    static let CMD_GET_TT_STATUS: UInt8 = 0x60
    static let CMD_SET_TT_POWER: UInt8 = 0x61
}

enum ServiceId {
    static let OTA: UInt8 = 0x01
    static let LOG: UInt8 = 0x02
    static let AT: UInt8 = 0x03
    static let SPP_VOICE: UInt8 = 0x04
    static let VOICE_TASK: UInt8 = 0x05
}
```

#### 数据包格式 (关键!)

**命令包格式:**
```
┌──────┬──────┬──────────┬──────┬───────┐
│ SEQ  │ CMD  │ DATA_LEN │ DATA │ CRC16 │
│ 1字节│ 1字节│   1字节  │ N字节│ 2字节 │
└──────┴──────┴──────────┴──────┴───────┘
最小包长: 5 字节 (无数据)

SEQ:  序列号，每条命令递增，响应时回显
CMD:  命令码 (见 SystemCommands)
DATA_LEN: 数据长度 (0-240)
DATA:  数据部分
CRC16: CRC16-CCITT 校验 (Little Endian: LSB在前)
```

**响应包格式:**
```
┌──────┬──────────┬────────┬──────────┬──────┬───────┐
│ SEQ  │ RESP_CODE│ RESULT │ DATA_LEN │ DATA │ CRC16 │
│ 1字节│   1字节  │  1字节 │   1字节  │ N字节│ 2字节 │
└──────┴──────────┴────────┴──────────┴──────┴───────┘
数据始终从偏移 4 开始

SEQ:  与请求包序列号匹配
RESP_CODE: 响应码 (通常是命令码的回显)
RESULT: 结果码 (0x00 = 成功)
DATA_LEN: 数据长度 (0-96)
DATA:  数据部分
CRC16: CRC16-CCITT 校验 (响应的 CRC 验证可跳过)
```

**SystemPacketBuilder 关键实现:**
```swift
final class SystemPacketBuilder {
    private static var sequenceNumber: UInt8 = 0

    /// 构建命令包
    static func buildCommand(cmd: UInt8, data: Data = Data()) -> Data {
        let seq = sequenceNumber
        sequenceNumber = (sequenceNumber &+ 1) & 0xFF

        // Header: SEQ + CMD + DATA_LEN + DATA
        var header = Data()
        header.append(seq)
        header.append(cmd)
        header.append(UInt8(data.count))
        header.append(data)

        // CRC16-CCITT (Little Endian)
        let crc = Crc16Ccitt.calculate(header)
        header.append(UInt8(crc & 0xFF))        // LSB first
        header.append(UInt8((crc >> 8) & 0xFF)) // MSB second

        return header
    }

    /// 解析响应包
    static func parseResponse(_ packet: Data) -> ParsedResponse? {
        guard packet.count >= 6 else { return nil }

        let seq = packet[0]
        let respCode = packet[1]
        let result = packet[2]
        let dataLen = min(Int(packet[3]), 96)

        // Data at offset 4
        let dataStart = 4
        let dataEnd = dataStart + dataLen
        let data = dataLen > 0 ? packet.subdata(in: dataStart..<dataEnd) : Data()

        return ParsedResponse(
            respCode: respCode,
            seq: seq,
            data: data,
            resultCode: result,
            crcValid: true  // Skip CRC verification per protocol
        )
    }
}
```

#### CRC16-CCITT
```swift
struct Crc16Ccitt {
    private static let POLYNOMIAL: UInt16 = 0x1021
    private static let INITIAL: UInt16 = 0xFFFF

    static func calculate(_ data: Data) -> UInt16 {
        var crc = INITIAL
        for byte in data {
            crc = crc ^ (UInt16(byte) << 8)
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ POLYNOMIAL
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }
}
```

### 2. 领域模型 (Domain Models) ✅

| 模型文件 | 内容 |
|---------|------|
| ConnectModels.swift | ConnectState, DeviceConnectionState, ScannedDevice, DeviceError |
| DeviceModels.swift | DeviceInfo, TerminalVersion, SystemInfo, BatteryInfo, SignalInfo |
| ModuleModels.swift | TtModuleState, TtModuleStatus, SimState, NetworkRegistrationStatus, BasebandVersion |
| CallModels.swift | CallState, ActiveCall, IncomingCall, DtmfKey, AudioMode, VoicePacket |
| SmsModels.swift | SmsNotification, SmsMessage, SmscConfig, SendingState |
| OtaModels.swift | OtaState, OtaTarget, OtaProgressInfo |
| AtModels.swift | AtResponse, AtNotification, NotificationType, AtResponseParser |

### 3. 服务客户端 (Service Clients) ✅

| 客户端 | 状态 | 说明 |
|--------|------|------|
| SystemServiceClientImpl | ✅ 完成 | 设备信息、电池、TT模块状态、服务控制 |
| AtServiceClientImpl | ✅ 完成 | AT 命令发送/响应、URC 通知 |
| VoiceServiceClientImpl | ✅ 完成 | 语音数据流、录音/播放、AMR-NB 编解码 |
| CallRecorderImpl | ✅ 完成 | 通话录音 (WAV, 8kHz, 16bit, mono) |
| OtaServiceClientImpl | ✅ 完成 | MCU/TT模块固件升级 |

### 4. BLE 管理器 ✅

| 功能 | 状态 |
|------|------|
| 设备扫描 | ✅ |
| 连接/断开 | ✅ |
| GATT 服务发现 | ✅ |
| 特征通知启用 | ✅ |
| 通知分发到客户端 | ✅ |
| 写入队列管理 | ✅ |
| MTU 协商 | ✅ |

### 5. OTA 升级协议

#### OTA 服务特征 (0xABF8)

| 特征 | UUID | 属性 | 用途 |
|------|------|------|------|
| OTA_CONTROL | 0xABF9 | Write + Notify | 启动/中止命令 |
| OTA_DATA | 0xABFA | Write | 固件数据包 |
| OTA_STATUS | 0xABFB | Notify | 进度/状态更新 |

#### OTA �

### 1. Manager 层实现
- DeviceManager
- CallManager
- SmsManager
- OtaManager
- SatelliteModuleManager

### 4. Repository 层实现
- DeviceRepository
- CallRepository
- MessageRepository

### 5. ViewModel 层
- HomeViewModel
- DialerViewModel
- SmsViewModel
- SettingsViewModel

## 与 Android 版本对比

| 组件 | Android | iOS | 状态 |
|------|---------|-----|------|
| BleUuid | ✅ | ✅ | 一致 |
| SystemCommands | ✅ | ✅ | 一致 |
| AtCommands | ✅ | ✅ | 一致 |
| SystemPacketBuilder | ✅ | ✅ | 一致 |
| CRC16-CCITT | ✅ | ✅ | 一致 |
| Domain Models | ✅ | ✅ | 一致 |
| BleManager | BleManagerImpl | BleManagerImpl | 结构一致 |
| SystemServiceClient | ✅ | ✅ | 一致 |
| AtServiceClient | ✅ | ✅ | 一致 |
| VoiceServiceClient | ✅ | ✅ | 一致 |
| CallRecorder | ✅ | ✅ | 一致 |
| OtaServiceClient | ✅ | ✅ | 一致 |

## 关键技术要点

### 1. 数据包格式
- **命令包**: SEQ + CMD + DATA_LEN + DATA + CRC16 (Little Endian)
- **响应包**: SEQ + RESP_CODE + RESULT + DATA_LEN + DATA + CRC16
- **数据偏移**: 响应数据始终从偏移 4 开始
- **CRC 跳过**: 响应 CRC 验证可跳过 (GATT 可能忽略)

### 2. CRC16-CCITT
- 多项式: 0x1021
- 初始值: 0xFFFF
- 字节序: Little Endian (LSB 在前)

### 3. BLE GATT 服务
- System Service (0xABFC): 设备信息、电池、TT模块状态
- AT Service (0xABF2): AT 命令代理
- Voice Service (0xABF0): 语音数据流
- OTA Service (0xABF8): 固件升级

### 4. iOS 特有注意事项
- 后台 BLE 扫描需要 `bluetooth-central` 后台模式
- 音频录制需要 `NSMicrophoneUsageDescription` 权限
- 蓝牙需要 `NSBluetoothAlwaysUsageDescription` 权限
- CoreBluetooth 不支持显式 MTU 请求，系统自动协商
- CoreBluetooth 不暴露连接优先级 API

## 下一步计划

1. **完成 OtaServiceClient** - 固件升级实现
2. **实现 Manager 层** - 业务逻辑封装
3. **实现 Repository 层** - 数据协调
4. **完善 ViewModel** - UI 状态管理
5. **连接真实设备测试** - 验证数据包格式

---
*最后更新: 2026-04-03*
*基于 CosmoCat Android 版本架构*
