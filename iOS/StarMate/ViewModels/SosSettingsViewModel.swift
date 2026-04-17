import Foundation
import CoreLocation
import Combine

// MARK: - SOS Settings ViewModel
@MainActor
class SosSettingsViewModel: ObservableObject {

    @Published var smsSlot1: String = ""
    @Published var smsSlot2: String = ""
    @Published var smsSlot3: String = ""
    @Published var callSlot1: String = ""
    @Published var callSlot2: String = ""
    @Published var callSlot3: String = ""
    @Published var smsCustom: String = ""

    @Published var previewBody: String = ""
    @Published var previewCharCount: Int = 0

    private let preferences: SosPreferences
    private var cancellables = Set<AnyCancellable>()

    // Location for preview
    private let locationManager = CLLocationManager()
    @Published var previewLat: Double?
    @Published var previewLon: Double?

    init(preferences: SosPreferences = .shared) {
        self.preferences = preferences
        loadFromPreferences()
        setupBindings()
        refreshPreviewCoordinates()
    }

    // MARK: - Load

    private func loadFromPreferences() {
        let s = preferences.slots
        smsSlot1 = s.smsSlots[0]
        smsSlot2 = s.smsSlots[1]
        smsSlot3 = s.smsSlots[2]
        callSlot1 = s.callSlots[0]
        callSlot2 = s.callSlots[1]
        callSlot3 = s.callSlots[2]
        smsCustom = s.smsCustom
        recomputePreview()
    }

    // MARK: - Bindings (auto-save with debounce)

    private func setupBindings() {
        // Observe all slot changes and persist
        $smsSlot1.sink { [weak self] _ in self?.persistSlots() }.store(in: &cancellables)
        $smsSlot2.sink { [weak self] _ in self?.persistSlots() }.store(in: &cancellables)
        $smsSlot3.sink { [weak self] _ in self?.persistSlots() }.store(in: &cancellables)
        $callSlot1.sink { [weak self] _ in self?.persistSlots() }.store(in: &cancellables)
        $callSlot2.sink { [weak self] _ in self?.persistSlots() }.store(in: &cancellables)
        $callSlot3.sink { [weak self] _ in self?.persistSlots() }.store(in: &cancellables)
        $smsCustom.sink { [weak self] _ in
            self?.persistSlots()
            self?.recomputePreview()
        }.store(in: &cancellables)
    }

    private func persistSlots() {
        var snapshot = SosSlotsSnapshot.empty()
        snapshot.smsSlots = [smsSlot1, smsSlot2, smsSlot3]
        snapshot.callSlots = [callSlot1, callSlot2, callSlot3]
        snapshot.smsCustom = smsCustom
        preferences.slots = snapshot
    }

    // MARK: - Preview

    func recomputePreview() {
        let custom = String(smsCustom.prefix(SosSlotsSnapshot.maxSmsContentLen))
        previewBody = SosPreviewTemplate.buildBody(
            customContent: custom,
            latitude: previewLat,
            longitude: previewLon
        )
        previewCharCount = previewBody.count
    }

    func refreshPreviewCoordinates() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startMonitoringSignificantLocationChanges()
        if let location = locationManager.location {
            previewLat = location.coordinate.latitude
            previewLon = location.coordinate.longitude
        }
        recomputePreview()
    }

    // MARK: - Slot snapshot for SOS trigger

    var currentSnapshot: SosSlotsSnapshot {
        var s = SosSlotsSnapshot.empty()
        s.smsSlots = [smsSlot1, smsSlot2, smsSlot3]
        s.callSlots = [callSlot1, callSlot2, callSlot3]
        s.smsCustom = smsCustom
        return s
    }
}
