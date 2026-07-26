import Foundation

public enum RelayCloudDeviceVaultError: Error, Equatable, Sendable {
    case invalidStoredDevices
}

public enum RelayCloudDeviceVault {
    public static func devices(
        in store: any SecretStoring
    ) throws -> [AdminCloudDeviceRegistration] {
        guard let encoded = try store.value(for: .cloudRootKeys) else {
            return []
        }
        guard
            let data = encoded.data(using: .utf8),
            let registrations = try? JSONDecoder().decode(
                [String: AdminCloudDeviceRegistration].self,
                from: data
            )
        else {
            throw RelayCloudDeviceVaultError.invalidStoredDevices
        }
        return registrations.values.sorted { $0.deviceId < $1.deviceId }
    }

    public static func upsert(
        _ registration: AdminCloudDeviceRegistration,
        in store: any SecretStoring
    ) throws {
        var registrations = Dictionary(
            uniqueKeysWithValues: try devices(in: store).map {
                ($0.deviceId, $0)
            }
        )
        registrations[registration.deviceId] = registration
        let data = try JSONEncoder().encode(registrations)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw RelayCloudDeviceVaultError.invalidStoredDevices
        }
        try store.set(encoded, for: .cloudRootKeys)
    }

    public static func removeAll(from store: any SecretStoring) throws {
        try store.remove(.cloudRootKeys)
    }

    public static func remove(
        deviceID: String,
        from store: any SecretStoring
    ) throws {
        var registrations = Dictionary(
            uniqueKeysWithValues: try devices(in: store).map {
                ($0.deviceId, $0)
            }
        )
        registrations.removeValue(forKey: deviceID)
        if registrations.isEmpty {
            try removeAll(from: store)
            return
        }
        let data = try JSONEncoder().encode(registrations)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw RelayCloudDeviceVaultError.invalidStoredDevices
        }
        try store.set(encoded, for: .cloudRootKeys)
    }
}
