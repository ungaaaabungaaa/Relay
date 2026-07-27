import Foundation

#if canImport(WatchKit)
import WatchKit
#endif

struct RelayHapticPreference {
    static let key = "relay.watch.haptics.enabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get {
            guard defaults.object(forKey: Self.key) != nil else { return true }
            return defaults.bool(forKey: Self.key)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.key)
        }
    }
}

#if canImport(WatchKit)
@MainActor
private let hapticPreference = RelayHapticPreference()

@MainActor
func playRelayHaptic(_ type: WKHapticType) {
    guard hapticPreference.isEnabled else { return }
    WKInterfaceDevice.current().play(type)
}
#endif
