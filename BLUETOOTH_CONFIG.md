# 蓝牙数据配置说明

## 📌 重要提示

当前代码已实现从真实蓝牙设备读取数据的功能，但**需要根据实际的 TTCat 设备协议进行调整**。

## 🔧 需要配置的内容

### 1. 蓝牙服务 UUID（必须修改）

**文件位置**：`Sources/StarMate/Services/BluetoothService.swift`

```swift
struct BluetoothService {
    // ⚠️ 请修改为实际设备的 Service UUID
    static let serviceUUID = CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")

    struct Characteristic {
        // ⚠️ 请修改为实际设备的 Characteristic UUIDs
        static let deviceInfo = CBUUID(string: "0000FFF1-0000-1000-8000-00805F9B34FB")
        static let batteryStatus = CBUUID(string: "0000FFF2-0000-1000-8000-00805F9B34FB")
        static let signalStatus = CBUUID(string: "0000FFF3-0000-1000-8000-00805F9B34FB")
        static let moduleStatus = CBUUID(string: "0000FFF4-0000-1000-8000-00805F9B34FB")
        static let networkStatus = CBUUID(string: "0000FFF5-0000-1000-8000-00805F9B34FB")
        static let command = CBUUID(string: "0000FFF6-0000-1000-8000-00805F9B34FB")
    }
}
```

### 2. 如何获取正确的 UUID

#### 方法 1：使用 LightBlue Explorer（推荐）

1. 在 App Store 下载 **LightBlue Explorer**
2. 打开应用，连接 TTCat 设备
3. 查看服务和特征列表
4. 记录下相关的 UUID 并更新代码

#### 方法 2：使用 nRF Connect（免费）

1. 在 App Store 下载 **nRF Connect**
2. 扫描并连接 TTCat 设备
3. 查看所有服务和特征
4. 找到可读/可通知的特征 UUID

### 3. 数据协议解析（必须调整）

**文件位置**：`Sources/StarMate/Services/BLEManager.swift`

需要根据实际设备的数据格式修改以下解析方法：

#### `parseDeviceInfoData(_ data: Data)`
```swift
private func parseDeviceInfoData(_ data: Data) {
    // 根据实际协议解析数据
    // 示例假设数据格式：[电量, 电压高字节, 电压低字节, 电流高字节, 电流低字节, 信号强度]
    guard data.count >= 6 else { return }

    let batteryLevel = Int(data[0])
    let voltageMv = Int(data[1]) * 100 + Int(data[2]) * 10
    let currentMa = Int(data[3]) * 100 + Int(data[4])
    let signalStrength = Int(data[5])

    // ... 更新 UI
}
```

#### 其他解析方法
- `parseBatteryData(_ data: Data)` - 电池状态数据
- `parseSignalData(_ data: Data)` - 信号强度数据
- `parseModuleData(_ data: Data)` - 模块状态数据
- `parseNetworkData(_ data: Data)` - 网络状态数据

### 4. 调试日志

应用会输出详细的蓝牙日志，包括：
- 发现的服务和特征 UUID
- 接收到的原始数据
- 解析结果

**查看日志**：
```bash
# 使用 Xcode 运行应用，查看控制台输出
# 或使用 Console.app 过滤 "StarMate"
```

## 🎯 测试步骤

1. **修改 UUID 配置**
   - 更新 `BluetoothService.swift` 中的 UUID

2. **连接设备**
   - 打开应用
   - 点击"搜索并连接 TTCat"
   - 选择设备连接

3. **查看日志**
   - 在 Xcode 控制台查看 UUID 匹配情况
   - 确认特征已发现

4. **验证数据**
   - 检查设备信息卡片是否显示真实数据
   - 测试刷新功能

## 🐛 常见问题

### Q: 连接成功但数据显示为 0 或默认值？
**A**: 可能的原因：
- UUID 配置不正确
- 需要发送命令才能触发数据上报（某些设备需要）
- 数据协议解析格式不对

### Q: 看不到特征被发现的日志？
**A**: 检查：
- Service UUID 是否正确
- 设备是否完全连接
- 是否需要配对

### Q: 如何知道数据格式？
**A**:
1. 查看设备厂商提供的协议文档
2. 使用 nRF Connect 手动读取特征，观察原始数据
3. 参考其他平台的实现（如 Android 版本）

## 📱 调试工具推荐

- **LightBlue Explorer** - iOS 蓝牙调试
- **nRF Connect** - 跨平台蓝牙调试（免费）
- **Bluetooth Explorer** - Mac 端蓝牙分析

## 💡 下一步

1. 获取正确的 UUID 和数据协议
2. 更新 `BluetoothService.swift`
3. 调整数据解析逻辑
4. 测试并验证功能

如果需要帮助，请提供：
- 设备的 Service UUID
- 各特征的 UUID
- 数据格式说明或原始数据样例
