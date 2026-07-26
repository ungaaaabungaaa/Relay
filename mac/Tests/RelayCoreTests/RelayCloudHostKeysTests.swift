import Foundation
import Testing
@testable import RelayCore

@Test
func cloudHostKeysAreStableSeparateP256IdentitiesInKeychain() throws {
    let backend = CloudKeysMemoryBackend()
    let store = KeychainStore(service: "test.relay.cloud-keys", backend: backend)
    let first = try RelayCloudHostKeys.loadOrCreate(in: store)
    let restored = try RelayCloudHostKeys.loadOrCreate(in: store)

    #expect(first.signingPublicKey == restored.signingPublicKey)
    #expect(first.agreementPublicKey == restored.agreementPublicKey)
    #expect(first.signingPublicKey != first.agreementPublicKey)
    #expect(first.fingerprint == restored.fingerprint)
    #expect(first.fingerprint.split(separator: ":").count == 4)
}

@Test
func approvedCloudDevicesRestoreFromKeychainWithoutLoggingRootKeys() throws {
    let store = KeychainStore(
        service: "test.relay.cloud-devices",
        backend: CloudKeysMemoryBackend()
    )
    let registration = AdminCloudDeviceRegistration(
        accountId: "account-1",
        hostId: "host-1",
        deviceId: "watch-1",
        name: "Watch6",
        signingPublicKey: "signing",
        rootKey: "root-key-material",
        metadata: AdminDeviceMetadata(
            platform: "wear-os",
            manufacturer: "Samsung",
            model: "Watch6",
            osVersion: "5",
            appVersion: "1",
            screenShape: "round"
        )
    )

    try RelayCloudDeviceVault.upsert(registration, in: store)
    #expect(try RelayCloudDeviceVault.devices(in: store) == [registration])
    #expect(!String(describing: RelayCloudDeviceVault.self).contains("root-key-material"))
    try RelayCloudDeviceVault.removeAll(from: store)
    #expect(try RelayCloudDeviceVault.devices(in: store).isEmpty)
}

private final class CloudKeysMemoryBackend: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func read(service: String, account: String) throws -> Data? {
        lock.withLock { values["\(service):\(account)"] }
    }

    func write(_ data: Data, service: String, account: String) throws {
        lock.withLock { values["\(service):\(account)"] = data }
    }

    func delete(service: String, account: String) throws {
        _ = lock.withLock { values.removeValue(forKey: "\(service):\(account)") }
    }
}
