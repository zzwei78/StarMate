import Foundation
import os.log

/// 日志工具，支持时间戳和日志级别
enum LogLevel: Int {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    var icon: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
}

/// 日志配置
struct LogConfig {
    static var minimumLevel: LogLevel = .info
    static var showTimestamp: Bool = true
    static var showModule: Bool = true

    /// 模块级别的日志开关
    static var moduleEnabled: [String: Bool] = [
        "BLE": true,
        "AT": true,
        "Voice": true,
        "CallManager": true,
        "AudioPipeline": true,
        "HomeView": false,
        "PlayNextFrame": false,  // 关闭高频日志
        "DEBUG": false,
        "Monitor": false
    ]
}

/// 日志工具
struct Log {
    /// 格式化时间戳
    private static func timestamp() -> String {
        guard LogConfig.showTimestamp else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    /// 打印日志
    private static func log(_ level: LogLevel, module: String, message: String) {
        // 检查日志级别
        if level.rawValue < LogConfig.minimumLevel.rawValue {
            return
        }

        // 检查模块开关
        for (key, enabled) in LogConfig.moduleEnabled {
            if module.contains(key) && !enabled {
                return
            }
        }

        var output = ""
        if LogConfig.showTimestamp {
            output += "[\(timestamp())] "
        }
        if LogConfig.showModule {
            output += "[\(module)] "
        }
        output += "\(level.icon) \(message)"

        print(output)
    }

    static func debug(_ module: String, _ message: String) {
        log(.debug, module: module, message: message)
    }

    static func info(_ module: String, _ message: String) {
        log(.info, module: module, message: message)
    }

    static func warning(_ module: String, _ message: String) {
        log(.warning, module: module, message: message)
    }

    static func error(_ module: String, _ message: String) {
        log(.error, module: module, message: message)
    }

    /// 快捷方法
    static func d(_ module: String, _ message: String) { debug(module, message) }
    static func i(_ module: String, _ message: String) { info(module, message) }
    static func w(_ module: String, _ message: String) { warning(module, message) }
    static func e(_ module: String, _ message: String) { error(module, message) }
}
