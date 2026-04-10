1. 项目概述
本模块负责 iOS App 与天通卫星终端硬件之间的实时语音双向传输。核心挑战在于将 iOS 原生音频流转换为卫星链路标准的 AMR-NB (8000Hz) 格式，并通过 BLE (Bluetooth Low Energy) 传输。

2. 技术栈约束
语言: Swift 6 (严格并发安全)

音频框架: AVFoundation (Audio Engine / Audio Unit)

编解码库: opencore-amr (C 语言静态库，通过 Bridging Header 接入)

蓝牙框架: CoreBluetooth (使用 GATT Profile)

采样率:

iOS 采集: 44100Hz 或 16000Hz (需重采样)

卫星链路: 固定 8000Hz, 16-bit PCM, Mono

3. 音频流水线架构 (Pipeline)
3.1 上行链路 (录音 -> 卫星)
Capture: 使用 AVAudioEngine 采集用户语音。

Resample: 将采集到的 PCM 降采样至 8000Hz。

Frame Slice: 将 PCM 数据切分为 20ms 的片段（160 个采样点）。

Encode: 调用 Encoder_Interface_Encode (opencore-amr) 将 PCM 转为 AMR-NB 帧。

注：去掉 AMR 文件头 #!AMR\n，只传输 Raw Frame。

BLE Transmit: 通过 writeValue(data, type: .withoutResponse) 发送。

3.2 下行链路 (卫星 -> 播放)
BLE Receive: 接收硬件传回的 20ms AMR 帧。

Decode: 调用 Decoder_Interface_decode 将 AMR 转回 PCM (8000Hz)。

Playback: 使用 AVAudioSourceNode 或 Audio Queue 将 PCM 推送至扬声器。

4. 接口定义 (待实现)
AudioPipelineManager.swift
Swift

protocol AudioPipelineDelegate: AnyObject {
    func didEncodeAMRFrame(_ frame: Data)
}

class AudioPipelineManager {
    // TODO: 实现 AVAudioEngine 采集逻辑
    // TODO: 实现 8000Hz 重采样逻辑
    // TODO: 接入 opencore-amr 编码接口
}
BluetoothManager.swift
Swift

class BluetoothManager: NSObject, CBCentralManagerDelegate {
    // TODO: 实现扫描与连接天通猫硬件逻辑
    // TODO: 设置连接优先级（iOS 自动管理，硬件端主动请求 Interval 15-30ms）
    // TODO: 实现数据包的分片与组装
}
5. 开发任务清单 (給 Claude 的指令)
Task 1: 编写 AudioResampler 类，将任意采样率的 AVAudioPCMBuffer 转换为 8000Hz/16bit/Mono。

Task 2: 封装 AMREncoder 包装器，调用 opencore-amr 的 C 接口处理 20ms 帧。

Task 3: 实现基于 CoreBluetooth 的发送队列，确保音频帧能够以恒定速率写入特征值（Characteristic），避免拥塞。

Task 4: 处理音频中断（如电话接入）和蓝牙断开的异常恢复逻辑。

6. 注意事项 (System Engineer Notes)
低延迟: 必须使用 .withoutResponse 写入蓝牙数据，减少链路往返开销。

内存管理: 16G Mac mini 环境下，避免在音频回调中进行大内存分配。

帧对齐: 必须严格遵守 20ms 一帧的步长，否则卫星端解码会产生爆音。