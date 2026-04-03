# CosmoCat / StarMate 架构设计文档

> 本文档描述 CosmoCat Android 版本的完整架构，供 StarMate iOS 版本设计参考。
> iOS 版本除了 UI 层和底层 BLE 接口外，其他架构、接口定义、中间层实现都可以保持一致。

---

## 1. 整体架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Presentation Layer                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  HomeView   │  │ DialerView  │  │  SMSView    │  │SettingsView │    │
│  │  HomeViewModel│ │DialerViewModel│ │SmsViewModel│  │SettingsViewModel│
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           Domain Layer                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      Repository Interfaces                       │   │
│  │  DeviceRepository │ CallRepository │ MessageRepository           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        Use Cases                                 │   │
│  │  ConnectDeviceUseCase │ SyncDeviceInfoUseCase │ MakeCallUseCase  │   │
│  │  SendMessageUseCase │ HandleIncomingCallUseCase                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      Manager Interfaces                          │   │
│  │  DeviceManager │ CallManager │ SmsManager │ OtaManager           │   │
│  │  SatelliteModuleManager │ SatellitePhoneManager                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        Domain Models                             │   │
│  │  DeviceModels │ CallModels │ SmsModels │ OtaModels │ AtModels   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            Data Layer                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Repository Implementations                    │   │
│  │  DeviceRepositoryImpl │ CallRepositoryImpl │ MessageRepositoryImpl│  │
│  └─────────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      Manager Implementations                     │   │
│  │  DeviceManagerImpl │ CallManagerImpl │ SmsManagerImpl            │   │
│  │  OtaManagerImpl │ SatelliteModuleManagerImpl │ SatellitePhone... │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                         BLE Layer                                │   │
│  │  BleManager │ SystemServiceClient │ AtServiceClient              │   │
│  │  VoiceServiceClient │ OtaServiceClient                           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                       Protocol Layer                             │   │
│  │  BleUuid │ SystemCommands │ AtCommands │ SystemPacketBuilder     │   │
│  │  Crc16Ccitt │ Crc16Modbus                                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                       Local Storage                              │   │
│  │  Room Database (CallRecord, Conversation, Message)               │   │
│  │  DataStore Preferences (DevicePreferences, RecordingPreferences) │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Platform Layer                                   │
│  Android: CoreBluetooth, AVAudioRecorder, MediaPlayer                   │
│  iOS:     CoreBluetooth, AVAudioEngine, AVAudioPlayer                   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. 分层职责

### 2.1 Presentation Layer (表现层)

| 组件 | 职责 |
|------|------|
| **Views** | SwiftUI 视图，纯 UI 渲染，用户交互 |
| **ViewModels** | 持有 UIState，订阅 Repository 的 StateFlow，处理用户操作，调用 UseCase/Repository |

**iOS 对应实现:**
- View: SwiftUI Views (`HomeView`, `DialerView`, `SMSView`, `SettingsView`)
- ViewModel: `ObservableObject` / `@Observable` 类

### 2.2 Domain Layer (领域层)

| 组件 | 职责 |
|------|------|
| **Repository Interfaces** | 定义数据访问抽象接口 |
| **Use Cases** | 单一职责的业务用例，协调多个 Manager |
| **Manager Interfaces** | 定义功能模块管理接口 |
| **Domain Models** | 纯数据模型，密封类表示状态机 |

**iOS 对应实现:**
- Protocol 定义接口
- struct/enum 定义数据模型（使用 Swift 的 enum 关联值实现 sealed class）

### 2.3 Data Layer (数据层)

| 组件 | 职责 |
|------|------|
| **Repository Impl** | 实现 Repository 接口，协调 Manager 和 DAO |
| **Manager Impl** | 实现业务逻辑，调用 BLE 客户端 |
| **BLE Clients** | GATT 服务客户端，处理特定服务的通信 |
| **Protocol** | 协议常量、命令构建、数据包解析 |
| **Local Storage** | Room/SQLite 数据库，DataStore/UserDefaults |

---

## 3. BLE GATT 服务架构

### 3.1 服务 UUID 定义

```swift
// BleUuid.swift - iOS 版本
enum BleUuid {
    // ========== Services ==========
    static let SYSTEM_SERVICE: CBUUID = CBUUID(string: "ABFC")
    static let AT_SERVICE: CBUUID = CBUUID(string: "ABF2")
    static let VOICE_SERVICE: CBUUID = CBUUID(string: "ABF0")
    static let OTA_SERVICE: CBUUID = CBUUID(string: "ABF8")

    // ========== System Service Characteristics ==========
    static let SYSTEM_CONTROL: CBUUID = CBUUID(string: "ABFD")  // Write + Notify
    static let SYSTEM_INFO: CBUUID = CBUUID(string: "ABFE")     // Read only (96 bytes)
    static let SYSTEM_STATUS: CBUUID = CBUUID(string: "ABFF")   // Notify

    // ========== AT Service Characteristics ==========
    static let AT_COMMAND: CBUUID = CBUUID(string: "ABF3")      // Write + Notify
    static let AT_RESPONSE: CBUUID = CBUUID(string: "ABF1")     // Notify

    // ========== Voice Service Characteristics ==========
    static let VOICE_IN: CBUUID = CBUUID(string: "ABEE")        // Write
    static let VOICE_OUT: CBUUID = CBUUID(string: "ABEF")       // Notify
    static let VOICE_DATA: CBUUID = CBUUID(string: "ABF1")      // Write + Notify (fallback)

    // ========== OTA Service Characteristics ==========
    static let OTA_CONTROL: CBUUID = CBUUID(string: "ABF9")     // Write
    static let OTA_DATA: CBUUID = CBUUID(string: "ABFA")        // Write
    static let OTA_STATUS: CBUUID = CBUUID(string: "ABFB")      // Notify

    // Device name filter
    static let DEVICE_NAME_FILTER = "TTCat"
}
```

### 3.2 服务架构图

```
┌──────────────────────────────────────────────────────────────────┐
│                         BleManager                                │
│  - 扫描设备 (scanDevices)                                         │
│  - 连接/断开 (connect/disconnect)                                 │
│  - MTU 协商 (requestMtu)                                          │
│  - 写入队列管理 (writeQueue)                                       │
│  - 通知分发 (dispatchNotification)                                │
└──────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ SystemService   │  │ AtServiceClient │  │ VoiceService    │
│ Client          │  │                 │  │ Client          │
│ (0xABFC)        │  │ (0xABF2)        │  │ (0xABF0)        │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│ - readInfo      │  │ - sendCommand   │  │ - sendVoiceData │
│ - readBattery   │  │ - responseFlow  │  │ - voiceDataFlow │
│ - startService  │  │ - urcFlow       │  │ - startRecording│
│ - getTtStatus   │  │                 │  │ - startPlaying  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │ OtaServiceClient│
                     │ (0xABF8)        │
                     ├─────────────────┤
                     │ - startMcuOta   │
                     │ - startTtOta    │
                     │ - progressFlow  │
                     └─────────────────┘
```

### 3.3 BleManager 接口定义

```swift
// BleManager.swift - iOS 版本
protocol BleManager {
    // 扫描设备
    func scanDevices() -> AsyncStream<ScannedDevice>

    // 连接设备
    func connect(_ deviceAddress: String) -> AsyncStream<ConnectState>

    // 断开连接
    func disconnect()

    // OTA 是否进行中
    func isOtaInProgress() -> Bool

    // 获取各服务客户端
    func getSystemClient() -> SystemServiceClient
    func getAtCommandClient() -> AtServiceClient
    func getVoiceClient() -> VoiceServiceClient
    func getOtaServiceClient() -> OtaServiceClient

    // MTU 请求
    func requestMtu(_ mtu: Int) async -> Result<Int, Error>

    // 读取 System Info 特征值
    func readSystemInfoCharacteristic() async -> Result<Data, Error>

    // 写入特征值并等待完成
    func writeCharacteristicAndWait(
        serviceUuid: CBUUID,
        charUuid: CBUUID,
        data: Data,
        writeType: CBCharacteristicWriteType,
        timeoutMs: Int64
    ) async -> Result<Void, Error>

    // 写入特征值不等待
    func writeCharacteristicNoWait(
        serviceUuid: CBUUID,
        charUuid: CBUUID,
        data: Data,
        writeType: CBCharacteristicWriteType
    )

    // 请求连接优先级
    func requestConnectionPriority(_ priority: Int) -> Bool

    // 重新发现服务
    func discoverServices() async -> Result<Void, Error>

    // 检查语音服务是否可用
    func isVoiceServiceAvailable() -> Bool
}
```

---

## 4. 服务客户端接口

### 4.1 SystemServiceClient (系统服务)

```swift
protocol SystemServiceClient {
    // 连接状态
    var connectionState: CurrentValueSubject<ConnectState, Never> { get }

    // 设备信息
    var deviceInfo: CurrentValueSubject<DeviceInfo?, Never> { get }

    // TT 模块状态
    var ttModuleState: CurrentValueSubject<TtModuleState?, Never> { get }

    // 读取设备信息 (0x30)
    func readInfo() async -> Result<SystemInfo, Error>

    // 读取版本信息 (0x31)
    func readVersionInfo() async -> Result<TerminalVersion, Error>

    // 读取电池状态
    func readBattery() async -> Result<BatteryInfo, Error>

    // 启动语音服务
    func startVoiceService() async -> Result<Void, Error>

    // 停止语音服务
    func stopVoiceService() async -> Result<Void, Error>

    // 获取服务状态
    func getServiceStatus(_ serviceId: UInt8) async -> Result<Bool, Error>

    // 启动 OTA 服务
    func startOtaService() async -> Result<Void, Error>

    // 重启 MCU
    func rebootMcu() async -> Result<Void, Error>

    // 重启 TT 模块
    func rebootModule() async -> Result<Void, Error>

    // 获取 TT 模块状态 (0x60)
    func getTtModuleStatus() async -> Result<TtModuleStatus, Error>

    // 设置 TT 模块电源 (0x61)
    func setTtModulePower(_ enabled: Bool) async -> Result<Void, Error>

    // GATT 断开时调用
    func onGattClosed()
}
```

### 4.2 AtServiceClient (AT 命令服务)

```swift
protocol AtServiceClient {
    // AT 响应流
    var responseFlow: AsyncStream<AtResponse> { get }

    // URC (非请求响应) 流
    var urcFlow: AsyncStream<AtNotification> { get }

    // 发送 AT 命令并等待响应
    func sendCommand(_ command: String) async -> Result<String, Error>

    // 发送 AT 命令 (自定义超时)
    func sendCommand(_ command: String, timeoutMs: Int64) async -> Result<String, Error>

    // 发送 AT 命令不等待响应
    func sendCommandNoWait(_ command: String) async -> Result<Void, Error>

    // GATT 断开时调用
    func onGattClosed()
}
```

### 4.3 VoiceServiceClient (语音服务)

```swift
protocol VoiceServiceClient {
    // 语音数据流 (接收)
    var voiceDataFlow: AsyncStream<VoicePacket> { get }

    // 发送语音数据
    func sendVoiceData(_ data: Data) async -> Result<Void, Error>

    // 开始录音
    func startRecording() async -> Result<Void, Error>

    // 停止录音
    func stopRecording() async -> Result<Void, Error>

    // 开始播放
    func startPlaying() async -> Result<Void, Error>

    // 停止播放
    func stopPlaying() async -> Result<Void, Error>

    // 切换音频输出模式
    func setAudioMode(_ mode: AudioMode) async -> Result<Void, Error>

    // GATT 断开时调用
    func onGattClosed()
}
```

### 4.4 OtaServiceClient (OTA 服务)

```swift
protocol OtaServiceClient {
    // OTA 状态
    var otaState: CurrentValueSubject<OtaState, Never> { get }

    // OTA 进度流 (0-100)
    var progressFlow: AsyncStream<Int> { get }

    // 开始 MCU OTA 升级
    func startMcuOta(_ firmware: Data, crc32: Int) async -> Result<Void, Error>

    // 开始 TT 模块 OTA 升级
    func startTtOta(_ firmware: Data, crc32: Int) async -> Result<Void, Error>

    // 中止 OTA
    func abortOta() async -> Result<Void, Error>

    // 重置状态为 Idle
    func resetOtaState()

    // 发送固件数据包
    func sendFirmwarePacket(seq: Int, data: Data) async -> Result<Void, Error>
}
```

---

## 5. Manager 层接口

### 5.1 DeviceManager (设备管理)

```swift
protocol DeviceManager {
    // 连接状态
    var connectionState: CurrentValueSubject<DeviceConnectionState, Never> { get }

    // 设备信息
    var deviceInfo: CurrentValueSubject<DeviceInfo?, Never> { get }

    // TT 模块状态
    var ttModuleState: CurrentValueSubject<TtModuleState?, Never> { get }

    // 连接设备
    func connect(_ deviceAddress: String) async -> Result<Void, Error>

    // 断开连接
    func disconnect() async -> Result<Void, Error>

    // 自动连接
    func autoConnect() async -> Result<Void, Error>

    // 重启设备
    func rebootDevice() async -> Result<Void, Error>

    // 获取系统信息
    func getSystemInfo() async -> Result<SystemInfo, Error>

    // 获取终端版本
    func getTerminalVersion() async -> Result<TerminalVersion, Error>

    // 刷新设备信息
    func refreshDeviceInfo() async -> Result<DeviceInfo, Error>

    // 获取电池信息
    func getBattery() async -> Result<BatteryInfo, Error>

    // 获取信号强度
    func getSignal() async -> Result<SignalInfo, Error>

    // 获取 TT 模块状态
    func getTtModuleStatus() async -> Result<TtModuleStatus, Error>

    // 设置 TT 模块电源
    func setTtModulePower(_ enabled: Bool) async -> Result<Void, Error>
}
```

### 5.2 CallManager (通话管理)

```swift
protocol CallManager {
    // 通话状态
    var callState: CurrentValueSubject<CallState, Never> { get }

    // 当前通话
    var currentCall: CurrentValueSubject<ActiveCall?, Never> { get }

    // 来电通知流
    var incomingCallFlow: AsyncStream<IncomingCall> { get }

    // 拨打电话
    func makeCall(_ phoneNumber: String) async -> Result<Void, Error>

    // 接听电话
    func answerCall() async -> Result<Void, Error>

    // 挂断电话
    func endCall() async -> Result<Void, Error>

    // 启用来电显示
    func enableCallerId() async -> Result<Void, Error>

    // 发送 DTMF
    func sendDtmf(_ dtmf: String) async -> Result<Void, Error>

    // 切换扬声器
    func toggleSpeaker() async -> Result<Void, Error>

    // 扬声器是否开启
    func isSpeakerOn() -> Bool
}
```

### 5.3 SmsManager (短信管理)

```swift
protocol SmsManager {
    // 新消息通知流
    var incomingMessageFlow: AsyncStream<SmsNotification> { get }

    // 发送状态流
    var sendingStateFlow: AsyncStream<SendingState> { get }

    // SMSC 配置
    var smscConfig: CurrentValueSubject<SmscConfig?, Never> { get }

    // 发送短信
    func sendMessage(_ phoneNumber: String, content: String) async -> Result<String, Error>

    // 查询消息列表
    func queryMessages() async -> Result<[SmsMessage], Error>

    // 读取单条消息
    func readMessage(_ index: Int) async -> Result<SmsMessage, Error>

    // 删除消息
    func deleteMessage(_ index: Int) async -> Result<Void, Error>

    // 获取 SMSC 号码
    func getSmsc() async -> Result<String, Error>

    // 设置 SMSC 号码
    func setSmsc(_ number: String) async -> Result<Void, Error>

    // 设置新消息指示
    func setNewMessageIndicator() async -> Result<Void, Error>
}
```

### 5.4 OtaManager (OTA 管理)

```swift
protocol OtaManager {
    // OTA 状态
    var otaState: CurrentValueSubject<OtaState, Never> { get }

    // OTA 进度流
    var progressFlow: AsyncStream<Int> { get }

    // 开始 MCU OTA
    func startMcuOta(_ firmwarePath: String) async -> Result<Void, Error>

    // 开始 TT 模块 OTA
    func startTtOta(_ firmwarePath: String) async -> Result<Void, Error>

    // 中止 OTA
    func abortOta() async -> Result<Void, Error>

    // 重置 OTA 状态
    func resetOtaState()
}
```

### 5.5 SatelliteModuleManager (卫星模块管理)

```swift
protocol SatelliteModuleManager {
    // 模块状态
    var moduleState: CurrentValueSubject<ModuleState, Never> { get }

    // 网络注册状态
    var networkRegistrationState: CurrentValueSubject<NetworkRegistrationStatus, Never> { get }

    // SIM 状态
    var simState: CurrentValueSubject<SimState?, Never> { get }

    // TT 模块状态
    var ttModuleState: CurrentValueSubject<TtModuleState?, Never> { get }

    // 信号强度 (0-5 格)
    var signalStrength: CurrentValueSubject<Int, Never> { get }

    // 原始 CSQ 值
    var signalCsqRaw: CurrentValueSubject<Int?, Never> { get }

    // 初始化模块
    func initModule() async -> Result<Void, Error>

    // 重启模块
    func rebootModule() async -> Result<Void, Error>

    // 获取信号
    func getSignal() async -> Result<Int, Error>

    // 查询网络注册状态
    func getNetworkRegistrationStatus() async -> Result<NetworkRegistrationStatus, Error>

    // 查询 SIM 状态
    func getSimStatus() async -> Result<SimState, Error>

    // 启用网络注册通知
    func enableRegistrationNotification() async -> Result<Void, Error>

    // 获取卫星模式
    func getSatelliteMode() async -> Result<SatelliteMode, Error>

    // 获取 TT 模块状态
    func getTtModuleStatus() async -> Result<TtModuleState, Error>

    // 设置 TT 模块电源
    func setTtModulePower(_ enabled: Bool) async -> Result<Void, Error>

    // 检查通信是否可用
    func isCommunicationAvailable() -> Bool

    // 清除连接派生状态
    func clearConnectionDerivedState()
}
```

### 5.6 SatellitePhoneManager (卫星电话管理)

```swift
protocol SatellitePhoneManager {
    // SIM 卡状态
    var simState: CurrentValueSubject<SimState, Never> { get }

    // 基带版本信息
    var basebandVersion: CurrentValueSubject<BasebandVersion?, Never> { get }

    // 获取 SIM 状态
    func getSimState() async -> Result<SimState, Error>

    // 输入 PIN 码
    func enterPin(_ pin: String) async -> Result<Void, Error>

    // 输入 PUK 码
    func enterPuk(_ puk: String, newPin: String) async -> Result<Void, Error>

    // 获取 IMEI
    func getIMEI() async -> Result<String, Error>

    // 获取 IMSI
    func getIMSI() async -> Result<String, Error>

    // 获取 CCID
    func getCCID() async -> Result<String, Error>

    // 获取基带软件版本
    func getBasebandSwVersion() async -> Result<String, Error>

    // 获取基带硬件版本
    func getBasebandHwVersion() async -> Result<String, Error>

    // 检查是否可以拨打电话
    func isReadyForCall() -> Bool
}
```

---

## 6. 领域模型 (Domain Models)

### 6.1 连接状态

```swift
// ConnectState.swift
enum ConnectState: Equatable {
    case disconnected
    case connecting(deviceAddress: String)
    case connected(deviceAddress: String, mtu: Int)
    case error(errorCode: Int, message: String)
}

// DeviceConnectionState.swift
enum DeviceConnectionState: Equatable {
    case disconnected
    case scanning(devices: [ScannedDevice])
    case connecting(deviceAddress: String)
    case connected(device: DeviceInfo)
    case error(error: DeviceError)
}

// ScannedDevice.swift
struct ScannedDevice: Equatable {
    let name: String
    let address: String
    let rssi: Int
}
```

### 6.2 设备模型

```swift
// DeviceInfo.swift
struct DeviceInfo: Equatable {
    let name: String
    let address: String
    let batteryLevel: Int        // 0-100
    let currentMa: Int           // Current in mA
    let voltageMv: Int           // Voltage in mV
    let signalStrength: Int      // 0-5 bars
    let isRegistered: Bool
    let regStatus: Int           // 0=未注册, 1=已注册, 2=搜索中, 3=拒绝, 4=未知, 5=漫游
    let satelliteMode: SatelliteMode
    let workMode: WorkMode
}

// TerminalVersion.swift
struct TerminalVersion: Equatable {
    let hardwareVersion: String
    let softwareVersion: String
    let firmwareVersion: String
    let manufacturer: String
    let modelNumber: String
}

// BatteryInfo.swift
struct BatteryInfo: Equatable {
    let level: Int
    let voltage: Int
    let current: Int
    let isCharging: Bool
    let isWirelessCharging: Bool
}

// SignalInfo.swift
struct SignalInfo: Equatable {
    let strength: Int       // 0-5 bars
    let ber: Int            // reserved / 0
    let isRegistered: Bool
    let regStatus: Int
}

// SatelliteMode.swift
enum SatelliteMode: String, Codable {
    case normal
    case transparent
    case otaUpgrade
}

// WorkMode.swift
enum WorkMode: String, Codable {
    case idle
    case calling
    case dataTransfer
}
```

### 6.3 TT 模块状态

```swift
// TtModuleState.swift
enum TtModuleState: Equatable {
    case hardwareFault(errorCode: Int)
    case initializing
    case waitingMuxResp
    case lowBatteryOff
    case userOff
    case working
    case updating
    case error(errorCode: Int)
    case poweredOff(reason: PowerOffReason)
}

// PowerOffReason.swift
enum PowerOffReason: String, Codable {
    case userRequest
    case lowBattery
    case hardwareFault
}

// TtModuleStatus.swift
struct TtModuleStatus: Equatable {
    let state: TtModuleState
    let voltageMv: Int
    @available(*, deprecated)
    var isPoweredOn: Bool = false
    @available(*, deprecated)
    var isMuxReady: Bool = false
    @available(*, deprecated)
    var isSimReady: Bool = false
    @available(*, deprecated)
    var isNetworkReady: Bool = false
}
```

### 6.4 通话模型

```swift
// CallState.swift
enum CallState: Equatable {
    case idle
    case dialing(phoneNumber: String)
    case incoming(phoneNumber: String)
    case connected(phoneNumber: String, startTime: Date)
    case ending(reason: EndReason)
}

// EndReason.swift
enum EndReason: String, Codable {
    case localHangup
    case remoteHangup
    case bleDisconnected
    case moduleError
}

// ActiveCall.swift
struct ActiveCall: Equatable {
    let phoneNumber: String
    let startTime: Date
    var isSpeakerOn: Bool = false
    let callState: CallState
}

// IncomingCall.swift
struct IncomingCall: Equatable {
    let phoneNumber: String
    let numberType: Int
    let name: String?
    let timestamp: Date
}
```

### 6.5 短信模型

```swift
// SmsNotification.swift
struct SmsNotification: Equatable {
    let storage: String
    let index: Int
    let timestamp: Date
}

// SmsMessage.swift
struct SmsMessage: Equatable, Identifiable {
    let id: Int
    let index: Int
    let phoneNumber: String
    let content: String
    let timestamp: Date
    let isRead: Bool
}

// SendingState.swift
enum SendingState: Equatable {
    case idle
    case sending(phoneNumber: String)
    case sent(messageRef: String)
    case failed(error: String)
}
```

### 6.6 SIM 卡状态

```swift
// SimState.swift
enum SimState: Equatable {
    case ready
    case simPinRequired(remainingAttempts: Int)
    case simPukRequired(remainingAttempts: Int)
    case simPin2Required(remainingAttempts: Int)
    case simPuk2Required(remainingAttempts: Int)
    case phSimPinRequired(remainingAttempts: Int)
    case absent
    case error
}

// NetworkRegistrationStatus.swift
enum NetworkRegistrationStatus: Equatable {
    case notRegistered
    case registered(isRoaming: Bool)
    case searching
    case registrationDenied
    case unknown
    case networkLost
}
```

### 6.7 OTA 模型

```swift
// OtaState.swift
enum OtaState: Equatable {
    case idle
    case writing(progress: Int)
    case verifying
    case success
    case failed(reason: String)
}

// OtaTarget.swift
enum OtaTarget: String, Codable {
    case mcu
    case ttModule
}
```

### 6.8 AT 命令模型

```swift
// AtResponse.swift
enum AtResponse: Equatable {
    case success(data: String)
    case error(code: Int, message: String)
    case cmeError(code: Int)
    case cmsError(code: Int)
    case timeout(command: String)
}

// AtNotification.swift
struct AtNotification: Equatable {
    let type: NotificationType
    let data: String
}

// NotificationType.swift
enum NotificationType: String, Codable {
    case callIncoming    // +CLIP / RING
    case smsReceived     // +CMTI
    case networkReg      // +CREG
    case callStatus      // +CLCC
    case unknown
}
```

---

## 7. 协议层

### 7.1 System 命令定义

```swift
// SystemCommands.swift
enum SystemCommands {
    // Battery and charging
    static let CMD_GET_BATTERY_INFO: UInt8 = 0x01
    static let CMD_GET_CHARGE_STATUS: UInt8 = 0x02
    static let CMD_GET_TT_SIGNAL: UInt8 = 0x03

    // Service management
    static let CMD_SERVICE_START: UInt8 = 0x10
    static let CMD_SERVICE_STOP: UInt8 = 0x11
    static let CMD_SERVICE_STATUS: UInt8 = 0x12

    // System control
    static let CMD_SYSTEM_REBOOT: UInt8 = 0x20
    static let CMD_REBOOT_MCU: UInt8 = 0x22
    static let CMD_REBOOT_TT: UInt8 = 0x23

    // System info
    static let CMD_GET_SYSTEM_INFO: UInt8 = 0x30
    static let CMD_GET_VERSION_INFO: UInt8 = 0x31

    // TT Module management (v3.1)
    static let CMD_GET_TT_STATUS: UInt8 = 0x60
    static let CMD_SET_TT_POWER: UInt8 = 0x61
}

// ServiceId.swift
enum ServiceId {
    static let OTA: UInt8 = 0x01
    static let LOG: UInt8 = 0x02
    static let AT: UInt8 = 0x03
    static let SPP_VOICE: UInt8 = 0x04
    static let VOICE_TASK: UInt8 = 0x05
}
```

### 7.2 AT 命令定义

```swift
// AtCommands.swift
enum AtCommands {
    // Basic
    static let AT = "AT"
    static let ATI = "ATI"

    // Device identification
    static let GET_MANUFACTURER = "AT+GMI"
    static let GET_MODEL = "AT+GMM"
    static let GET_SW_VERSION = "AT+GMR"
    static let GET_HW_VERSION = "AT^HVER"
    static let GET_IMEI = "AT+GSN"
    static let GET_IMSI = "AT+CIMI"

    // SIM card
    static let GET_SIM_STATE = "AT+CPIN?"
    static func enterPin(_ pin: String) -> String { "AT+CPIN=\"\(pin)\"" }
    static func enterPuk(_ puk: String, _ newPin: String) -> String { "AT+CPIN=\"\(puk)\",\"\(newPin)\"" }

    // Network
    static let GET_SIGNAL = "AT+CSQ"
    static let GET_NETWORK_REG = "AT+CREG?"
    static let ENABLE_NETWORK_REG_NOTIFY = "AT+CREG=2"
    static let GET_OPERATOR = "AT+COPS?"

    // Call management
    static func dial(_ number: String) -> String { "ATD\(number);" }
    static let ANSWER = "ATA"
    static let HANGUP = "AT+CHUP"
    static let GET_CALL_LIST = "AT+CLCC"
    static let ENABLE_CALLER_ID = "AT+CLIP=1"
    static func sendDtmf(_ dtmf: String) -> String { "AT+VTS=\"\(dtmf)\"" }

    // SMS management
    static let SET_TEXT_MODE = "AT+CMGF=1"
    static func sendSms(_ number: String) -> String { "AT+CMGS=\"\(number)\",129" }
    static let GET_ALL_SMS = "AT+CMGL=\"ALL\""
    static let GET_UNREAD_SMS = "AT+CMGL=\"REC UNREAD\""
    static func readSms(_ index: Int) -> String { "AT+CMGR=\(index)" }
    static func deleteSms(_ index: Int) -> String { "AT+CMGD=\(index)" }
    static let DELETE_ALL_SMS = "AT+CMGD=1,4"
    static let SET_NEW_MSG_INDICATOR = "AT+CNMI=2,1,0,0,0"
    static let GET_SMSC = "AT+CSCA?"
    static func setSmsc(_ number: String, _ type: Int = 129) -> String { "AT+CSCA=\"\(number)\",\(type)" }

    // Control characters
    static let CTRL_Z = "\u{1A}"
    static let CR = "\r"
}
```

### 7.3 数据包格式

```
命令包格式:
┌──────┬──────┬──────────┬──────┬───────┐
│ SEQ  │ CMD  │ DATA_LEN │ DATA │ CRC16 │
│ 1字节│ 1字节│   1字节  │ N字节│ 2字节 │
└──────┴──────┴──────────┴──────┴───────┘

响应包格式:
┌──────┬──────────┬────────┬──────────┬──────┬───────┐
│ SEQ  │ RESP_CODE│ RESULT │ DATA_LEN │ DATA │ CRC16 │
│ 1字节│   1字节  │  1字节 │   1字节  │ N字节│ 2字节 │
└──────┴──────────┴────────┴──────────┴──────┴───────┘
```

### 7.4 CRC16 计算

```swift
// Crc16Ccitt.swift
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
                crc = crc & 0xFFFF
            }
        }
        return crc
    }
}

// Crc16Modbus.swift (用于 OTA)
struct Crc16Modbus {
    private static let POLYNOMIAL: UInt16 = 0xA001
    private static let INITIAL: UInt16 = 0xFFFF

    static func calculate(_ data: Data) -> UInt16 {
        var crc = INITIAL
        for byte in data {
            crc = crc ^ UInt16(byte)
            for _ in 0..<8 {
                if (crc & 0x0001) != 0 {
                    crc = (crc >> 1) ^ POLYNOMIAL
                } else {
                    crc = crc >> 1
                }
            }
        }
        return crc
    }
}
```

---

## 8. 依赖注入 (DI)

### 8.1 Android (Hilt) 模块结构

```kotlin
// 模块依赖关系
BleModule ──────► 提供 BleManager, ServiceClients
    │
    ▼
ManagerModule ──► 提供 DeviceManager, CallManager, SmsManager, OtaManager
    │
    ▼
RepositoryModule ► 提供 DeviceRepository, CallRepository, MessageRepository
```

### 8.2 iOS (Swift DI) 建议

使用 Swift 的依赖注入方案 (如 Swinject, Needle, 或手动 DI):

```swift
// DependencyContainer.swift
class DependencyContainer {
    // MARK: - BLE Layer
    lazy var bleManager: BleManager = BleManagerImpl(
        systemClient: systemServiceClient,
        atClient: atServiceClient,
        voiceClient: voiceServiceClient,
        otaClient: otaServiceClient
    )

    lazy var systemServiceClient: SystemServiceClient = SystemServiceClientImpl()
    lazy var atServiceClient: AtServiceClient = AtServiceClientImpl()
    lazy var voiceServiceClient: VoiceServiceClient = VoiceServiceClientImpl()
    lazy var otaServiceClient: OtaServiceClient = OtaServiceClientImpl()

    // MARK: - Manager Layer
    lazy var deviceManager: DeviceManager = DeviceManagerImpl(
        bleManager: bleManager,
        systemClient: systemServiceClient,
        satelliteModuleManager: satelliteModuleManager,
        devicePreferences: devicePreferences,
        otaManager: otaManager
    )

    lazy var callManager: CallManager = CallManagerImpl(
        atClient: atServiceClient,
        systemClient: systemServiceClient,
        voiceClient: voiceServiceClient,
        bleManager: bleManager,
        callRecorder: callRecorder,
        recordingPreferences: recordingPreferences
    )

    lazy var smsManager: SmsManager = SmsManagerImpl(atClient: atServiceClient)
    lazy var otaManager: OtaManager = OtaManagerImpl(otaClient: otaServiceClient, systemClient: systemServiceClient, bleManager: bleManager)
    lazy var satelliteModuleManager: SatelliteModuleManager = SatelliteModuleManagerImpl(systemClient: systemServiceClient, atClient: atServiceClient)

    // MARK: - Repository Layer
    lazy var deviceRepository: DeviceRepository = DeviceRepositoryImpl(deviceManager: deviceManager, satelliteModuleManager: satelliteModuleManager)
    lazy var callRepository: CallRepository = CallRepositoryImpl(callManager: callManager, callRecordDao: callRecordDao)
    lazy var messageRepository: MessageRepository = MessageRepositoryImpl(smsManager: smsManager, conversationDao: conversationDao, messageDao: messageDao)

    // MARK: - Storage
    lazy var database: AppDatabase = AppDatabase()
    lazy var devicePreferences: DevicePreferences = DevicePreferences()
    lazy var recordingPreferences: RecordingPreferences = RecordingPreferences()
}
```

---

## 9. 数据流

### 9.1 设备连接流程

```
用户点击扫描
    │
    ▼
HomeViewModel.startScan()
    │
    ▼
BleManager.scanDevices() ───► Flow<ScannedDevice>
    │
    ▼
用户选择设备
    │
    ▼
HomeViewModel.connectDevice(address)
    │
    ▼
ConnectDeviceUseCase(address)
    │
    ▼
DeviceRepository.connect(address)
    │
    ▼
DeviceManager.connect(address)
    │
    ▼
BleManager.connect(address) ───► Flow<ConnectState>
    │
    ├──► STATE_CONNECTED
    │        │
    │        ▼
    │    discoverServices()
    │        │
    │        ▼
    │    requestMtu(247)
    │        │
    │        ▼
    │    enableAllNotifications()
    │        │
    │        ▼
    │    systemServiceClient.onGattReady()
    │    atServiceClient.onGattReady()
    │    voiceServiceClient.onGattReady()
    │    otaServiceClient.onGattReady()
    │        │
    │        ▼
    │    ConnectState.Connected(address, mtu)
    │
    └──► UI 更新
```

### 9.2 拨打电话流程

```
用户输入号码并拨打
    │
    ▼
DialerViewModel.makeCall(phoneNumber)
    │
    ▼
MakeCallUseCase(phoneNumber)
    │
    ▼
CallRepository.makeCall(phoneNumber)
    │
    ▼
CallManager.makeCall(phoneNumber)
    │
    ├──► CallState = Dialing
    │
    ▼
AtServiceClient.sendCommand("ATD{number};")
    │
    ▼
等待 AT 响应
    │
    ├──► OK ───► CallState = Connected
    │                │
    │                ▼
    │           VoiceServiceClient.startRecording()
    │           VoiceServiceClient.startPlaying()
    │
    └──► ERROR ───► CallState = Idle
```

### 9.3 发送短信流程

```
用户输入短信内容并发送
    │
    ▼
SmsViewModel.sendMessage(phoneNumber, content)
    │
    ▼
SendMessageUseCase(phoneNumber, content)
    │
    ▼
MessageRepository.sendMessage(phoneNumber, content)
    │
    ▼
SmsManager.sendMessage(phoneNumber, content)
    │
    ├──► SendingState = Sending
    │
    ▼
AtServiceClient.sendCommand("AT+CMGF=1")
    │
    ▼
AtServiceClient.sendCommand("AT+CMGS=\"{number}\",129")
    │
    ▼
AtServiceClient.sendCommand("{content}\u{1A}")
    │
    ▼
等待 +CMGS: <mr> OK
    │
    ├──► Success ───► SendingState = Sent(messageRef)
    │
    └──► Error ───► SendingState = Failed(error)
```

---

## 10. iOS vs Android 平台差异

| 层级 | Android | iOS |
|------|---------|-----|
| **UI** | Jetpack Compose | SwiftUI |
| **BLE** | Android BluetoothGatt | CoreBluetooth (CBCentralManager, CBPeripheral) |
| **音频** | MediaCodec, AudioRecord, MediaPlayer | AVAudioEngine, AVAudioRecorder, AVAudioPlayer |
| **数据库** | Room (SQLite) | SwiftData / Core Data / GRDB.swift |
| **偏好存储** | DataStore | UserDefaults / SwiftData |
| **DI** | Hilt (Dagger) | Swinject / Needle / 手动 DI |
| **异步** | Kotlin Coroutines, Flow | Swift Concurrency (async/await, AsyncStream) |
| **状态管理** | StateFlow, MutableStateFlow | @Published, CurrentValueSubject, @Observable |

---

## 11. iOS 实现建议

### 11.1 目录结构

```
StarMate/
├── StarMateApp.swift
├── ContentView.swift
│
├── Domain/
│   ├── Models/
│   │   ├── ConnectState.swift
│   │   ├── DeviceModels.swift
│   │   ├── CallModels.swift
│   │   ├── SmsModels.swift
│   │   ├── OtaModels.swift
│   │   ├── AtModels.swift
│   │   └── ModuleModels.swift
│   │
│   ├── Repositories/
│   │   ├── DeviceRepository.swift
│   │   ├── CallRepository.swift
│   │   └── MessageRepository.swift
│   │
│   ├── Managers/
│   │   ├── DeviceManager.swift
│   │   ├── CallManager.swift
│   │   ├── SmsManager.swift
│   │   ├── OtaManager.swift
│   │   ├── SatelliteModuleManager.swift
│   │   └── SatellitePhoneManager.swift
│   │
│   └── UseCases/
│       ├── ConnectDeviceUseCase.swift
│       ├── SyncDeviceInfoUseCase.swift
│       ├── MakeCallUseCase.swift
│       └── SendMessageUseCase.swift
│
├── Data/
│   ├── BLE/
│   │   ├── BleManager.swift
│   │   ├── BleUuid.swift
│   │   ├── Clients/
│   │   │   ├── SystemServiceClient.swift
│   │   │   ├── AtServiceClient.swift
│   │   │   ├── VoiceServiceClient.swift
│   │   │   └── OtaServiceClient.swift
│   │   └── Protocol/
│   │       ├── SystemCommands.swift
│   │       ├── AtCommands.swift
│   │       ├── SystemPacketBuilder.swift
│   │       └── Crc16.swift
│   │
│   ├── Repositories/
│   │   ├── DeviceRepositoryImpl.swift
│   │   ├── CallRepositoryImpl.swift
│   │   └── MessageRepositoryImpl.swift
│   │
│   ├── Managers/
│   │   ├── DeviceManagerImpl.swift
│   │   ├── CallManagerImpl.swift
│   │   ├── SmsManagerImpl.swift
│   │   ├── OtaManagerImpl.swift
│   │   └── SatelliteModuleManagerImpl.swift
│   │
│   └── Storage/
│       ├── Database/
│       │   ├── AppDatabase.swift
│       │   └── Entities/
│       │       ├── CallRecord.swift
│       │       ├── Conversation.swift
│       │       └── Message.swift
│       └── Preferences/
│           ├── DevicePreferences.swift
│           └── RecordingPreferences.swift
│
├── Presentation/
│   ├── Theme/
│   │   ├── ColorScheme.swift
│   │   └── AppTheme.swift
│   │
│   ├── Home/
│   │   ├── HomeView.swift
│   │   └── HomeViewModel.swift
│   │
│   ├── Dialer/
│   │   ├── DialerView.swift
│   │   └── DialerViewModel.swift
│   │
│   ├── SMS/
│   │   ├── SMSView.swift
│   │   └── SmsViewModel.swift
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   └── SettingsViewModel.swift
│   │
│   └── Navigation/
│       └── NavRoutes.swift
│
├── DI/
│   └── DependencyContainer.swift
│
└── Resources/
    ├── Assets.xcassets
    └── Info.plist
```

### 11.2 关键实现要点

1. **BLE 层**: 使用 CoreBluetooth 框架，实现 `BleManagerImpl` 类
2. **异步**: 使用 Swift Concurrency (async/await, AsyncStream, Actor)
3. **状态管理**: 使用 `@Observable` (iOS 17+) 或 `ObservableObject`
4. **数据存储**: 使用 SwiftData (iOS 17+) 或 GRDB.swift
5. **依赖注入**: 手动 DI 或使用 Swinject

---

## 12. 总结

### 可复用部分 (100% 一致)

- ✅ **BleUuid** - UUID 定义完全一致
- ✅ **SystemCommands / AtCommands** - 命令常量完全一致
- ✅ **Domain Models** - 数据模型结构完全一致
- ✅ **Protocol** - 数据包格式、CRC 算法完全一致
- ✅ **接口定义** - Manager/Repository/Client 接口签名一致

### 需要适配部分

- 🔄 **BleManager 实现** - CoreBluetooth vs Android BluetoothGatt
- 🔄 **VoiceServiceClient** - AVAudioEngine vs MediaCodec
- 🔄 **数据库** - SwiftData/GRDB vs Room
- 🔄 **DI 容器** - 手动/Swinject vs Hilt

### iOS 特有注意

- ⚠️ 后台 BLE 扫描需要 `bluetooth-central` 后台模式
- ⚠️ 音频录制需要 `NSMicrophoneUsageDescription` 权限
- ⚠️ 蓝牙需要 `NSBluetoothAlwaysUsageDescription` 权限

---

*文档版本: 1.0*
*最后更新: 2026-04-03*
*基于 CosmoCat Android 版本架构*
