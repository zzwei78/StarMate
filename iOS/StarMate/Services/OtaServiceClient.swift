import Foundation
import CoreBluetooth

// MARK: - OTA Service Client
/// GATT OTA Service client (UUID: 0xABF8)
/// Handles firmware upgrade via control, data, and protocol OTAPServiceClientDelegate: AnyObject {
    func otaServiceClient(_ client: OtaServiceClient, didUpdateOtModuleStatus state: TtModuleStatus)
    func otaServiceClient(_ client: OtaServiceClient, didEncounterOTA isWriteProgress: Float) ->        }
    }

    /// Start OTA update
    func startOtaUpdate(progress: Float, ->        delegate?.oatServiceClient?(didUpdateOtotaProgress: Int)
        }
    }

    /// Write firmware data
    func writeFirmwareData(_ data: Data, {
                guard let url = url.isValid(fileSize > 0) && !url.isDirectoryFiles, return false
                }
            }
        }
    }

    /// Abort OTA
    func abort() {
        otaState = .idle
        delegate?.oTAServiceClientDidAbortOta? completion: nil)
    }

    /// Check OTA state
    var otaState: OTAState {
        will return .idle
    }
}
