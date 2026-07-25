import Foundation
import Testing
@testable import RelayWatchCore

@Test
func p256PublicKeyUsesSubjectPublicKeyInfoEncoding() throws {
    let rawPoint = Data([0x04] + Array(repeating: 0x11, count: 64))

    let encoded = try relaySubjectPublicKeyInfo(rawPoint)

    #expect(encoded.count == 91)
    #expect(
        encoded.prefix(26) == Data([
            0x30, 0x59,
            0x30, 0x13,
            0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
            0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00,
        ])
    )
    #expect(encoded.suffix(65) == rawPoint)
}

@Test
func p256PublicKeyRejectsMalformedRawPoint() {
    #expect(throws: RelayWatchIdentityError.publicKeyUnavailable) {
        try relaySubjectPublicKeyInfo(Data(repeating: 0x00, count: 65))
    }
}
