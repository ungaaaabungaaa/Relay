import CryptoKit
import Foundation

enum RelayWatchScreen: String, CaseIterable, Identifiable {
    case onboarding
    case pairing
    case inbox
    case approval
    case question
    case tasks
    case activity
    case instruction
    case voice
    case newTask
    case history
    case settings
    case revoked

    var id: Self { self }

    var title: String {
        switch self {
        case .onboarding: "Welcome"
        case .pairing: "Pair Mac"
        case .inbox: "Inbox"
        case .approval: "Approval"
        case .question: "Question"
        case .tasks: "Tasks"
        case .activity: "Activity"
        case .instruction: "Instruction"
        case .voice: "Voice"
        case .newTask: "New task"
        case .history: "History"
        case .settings: "Settings"
        case .revoked: "Revoked"
        }
    }

    var symbol: String {
        switch self {
        case .onboarding: "hand.wave"
        case .pairing: "link"
        case .inbox: "tray.full"
        case .approval: "checkmark.shield"
        case .question: "questionmark.bubble"
        case .tasks: "terminal"
        case .activity: "waveform.path.ecg"
        case .instruction: "text.bubble"
        case .voice: "mic"
        case .newTask: "plus.circle"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        case .revoked: "lock.slash"
        }
    }
}

enum RelayConnectionState: Equatable {
    case unpaired
    case pairing
    case live
    case offline
    case revoked
    case incompatible
}

struct RelayPairingRecord: Equatable {
    let origin: URL
    let discoveryToken: String
    let apiVersion: Int

    static func decode(_ attributes: [String: Data]) -> RelayPairingRecord? {
        guard
            let originText = attributes["origin"].flatMap({
                String(data: $0, encoding: .utf8)
            }),
            let origin = URL(string: originText),
            origin.scheme == "https",
            origin.host != nil,
            let token = attributes["token"].flatMap({
                String(data: $0, encoding: .utf8)
            }),
            token.range(
                of: #"^[a-f0-9]{32}$"#,
                options: .regularExpression
            ) != nil,
            let apiText = attributes["api"].flatMap({
                String(data: $0, encoding: .utf8)
            }),
            let apiVersion = Int(apiText),
            apiVersion == 1
        else {
            return nil
        }
        return RelayPairingRecord(
            origin: origin,
            discoveryToken: token,
            apiVersion: apiVersion
        )
    }
}

struct RelayMacIdentity: Decodable, Equatable {
    let macName: String
    let macFingerprint: String
    let apiVersion: Int
    let expiresAt: Int64
}

struct RelayPendingPairing: Decodable {
    let pairingId: String
    let pollToken: String
    let expiresAt: Int64
}

struct RelayPairingStatus: Decodable {
    let state: String
    let deviceId: String?
    let origin: URL?
    let apiVersion: Int?
}

struct RelayDeviceMetadata: Encodable {
    let platform = "watch-os"
    let manufacturer = "Apple"
    let model: String
    let osVersion: String
    let appVersion: String
    let screenShape = "round"
}

func relayCanonicalRequest(
    deviceID: String,
    method: String,
    path: String,
    body: Data,
    timestamp: Int64,
    nonce: String
) -> Data {
    let digest = SHA256.hash(data: body)
        .map { String(format: "%02x", $0) }
        .joined()
    return Data(
        [
            deviceID,
            method.uppercased(),
            path,
            digest,
            String(timestamp),
            nonce,
        ].joined(separator: "\n").utf8
    )
}
