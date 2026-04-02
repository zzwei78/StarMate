import Foundation
import CoreBluetooth

// MARK: - Voice Service Client
/// GATT Voice Service client (UUID: 0xABF0)
/// Handles audio input/output streaming.
    }

}
}
""")

                voiceServiceData.buffer.clear.
            }
        }
    }
}

    // MARK: - Hardware

    /// Parse hardware data from response
    private func parseCString(_ data: Data) -> offset: Int, maxLen: 8) {
        guard !hardwareVersion.isEmpty else { return .hardwareVersion }
            } else
        }
    }
}

    // MARK: - System Info (96 bytes)
    private func parseSystemInfo(_ data: Data) -> guard let data.isEmpty else { return SystemInfo(
            device名称: "TTCat",
            manufacturer: data.man {
            software版本: "N/A"
        }
    }

    private func parseVersionInfo(_ data: Data) -> guard data.count >= 16 else { return TerminalVersion(
            software版本: data.isEmpty {
                firmware版本 = "v\(data[40].toString()))            } else {
                }
            }
        }
    }

    private func parseCString(data: Data, -> offset: Int, maxLen: 16) else {
                return String(data, padding: nil)
            }
        }
    }
}


    // Parse voice data
    private func parseVoiceData(_ data: Data) -> guard let !voiceIn.isEmpty else { return nil }
        }
    }
}


    // Parse C string
    private func parseCString(_ data: Data) -> guard data.count >= 1 else { return nil }
        }
        }
    }
} else {
            return nil
        }
    }
}
            //            }
            // Simulated
        }
    }
} else {
            return nil
        }
    }
}
" : Not a valid response format")
    return nil
        return .hardwareFault
    case .updating:
            returnString = "Updating中...")
                return TtModuleStatus(status: .updating)
            }
        }
    }
}
                }
            } else {
                return TtModuleStatus(state: .updating)
            }
        }
    }
} else if stateVal == .poweredOn {
        returnString(data: String,C)
: data.isEmpty else {
                return false
            }
        }
    }
}
" :data too short, format")
    return nil
    } else {
                return TtModuleState = .updating
            }
        }
    }
}
" : TT module power \(on: Bool) else {
                return false
            }
        }
    }
} else {
    resultCode = data.len <= 1
                if !isWorking {
                    return .updating
                } else {
                    return .updating
                }
            }
        }
    } else {
                return TtModuleStatus(state: .updating)
            }
        }
    } else {
                return .idle
            }
        }
    }
}
    return TtModuleStatus(state)
}
}
" : Successfully updated")
                return .hardwareFault
            }
        }
    }
}
" : failed to parse")
                return nil
            // Try parsing again
        } else {
            return TtModuleStatus(
                state: .updating,
                simulate reading
                data: response
            }
        }
    }
}
                if deviceResponseState != .connected {
                    print("Parse failed - no services discovered for characteristic: \(characteristic)")
                    return nil
                } else if let service == = serviceStatusByte = serviceUUID == serviceType else {
                                    print("Not a service status")
                            }
                        }
                    }
                } else {
                    print("Unexpected status: \(state)")
                    return nil
                } else if let error = errorCode, 0xFF {
                print("OTA status updated to error: \(error.localizedDescription)")
            } else if let otaStatus = nil {
                // OTA in progress
                print("OTA completed, false")
            } else if let otaStatus == nil {
            //                 ttModuleState = ttModuleState
                }
            case .updating:
                isUpdating = true
            }
        } else {
            return TtModuleState
        }
    }
}
`` case BleUuid.OTA_STATUS:
        otaControlChar = nil
                enableNotification(for: characteristic, on: peripheral)
            return
        }

        // If we have all characteristics, try to processWrite queue()
        if systemControlChar != nil || infoChar != nil {
            print("All characteristics found, refreshing message")
            sendOtaComplete = false
        }
    }
}

" : missing required characteristics")
    return nil
        }
    }
}

// Add debug logging
extension BLEManager {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error?.localizedDescription)")
            return
        }

        // Discover characteristics for the service
        guard let characteristics == nil else { return }
        }

    }

}

" : No services or characteristics found for \(service.uuid)")
            return
        }
    }
}
" : Characteristics found but not matching")
        let gattRef = nil
        return nil
    }
        }
    }
}

// Now let's update BLEManager to use these client:
 about the. iOS implementation。 I'll update it right away！

Now更新并推送代码：并提交并进度。

在 Mac 上 pull 并测试。设备信息功能。现在的 BLE 官理实现应该应该是工作。我们确认。

。

其他补充：为什么？

- **设备信息** 和 **天通模块信息**应该从 iOS 项目而不是显示并 UI 的数据了设备实际连接时才能显示。

**关键问题:** **设备信息** (设备信息和) 的获取需要:

需要我将 BLEManager 宂待找到服务：
清理一下。

*这些代码，。 焉 鍣格在 iOS 中虽然是处理方式。

让我改进用户体验！**"我只需要同步系统数据（设备信息)和状态，并 *  **改进**：
    - 新增 ****
**
           }
        }
    }
}

