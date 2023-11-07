//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class ECKeyPairTest: XCTestCase {
    func testEncodeDecode() throws {
        let privateKey = try PrivateKey(Array(repeating: 0, count: 31) + [0x41])
        let keyPair = ECKeyPair(IdentityKeyPair(publicKey: privateKey.publicKey, privateKey: privateKey))

        let encodedData = try NSKeyedArchiver.archivedData(withRootObject: keyPair, requiringSecureCoding: true)
        let decodedKeyPair = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: ECKeyPair.self, from: encodedData, requiringSecureCoding: true))

        XCTAssertEqual(decodedKeyPair.identityKeyPair.privateKey.serialize(), keyPair.identityKeyPair.privateKey.serialize())
        XCTAssertEqual(decodedKeyPair.identityKeyPair.publicKey, keyPair.identityKeyPair.publicKey)
    }

    func testStableDecoding() throws {
        let privateKey = try PrivateKey(Array(repeating: 0, count: 31) + [0x41])
        let keyPair = ECKeyPair(IdentityKeyPair(publicKey: privateKey.publicKey, privateKey: privateKey))

        let encodedData = try XCTUnwrap(Data(
            base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGjCwwTVSRudWxs0w0ODxAREl8QFVRTRUNLZXlQYWlyUHJpdmF0ZUtleV8QFFRTRUNLZXlQYWlyUHVibGljS2V5ViRjbGFzc08QIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABBTxAg/TOE4TKtAqVsePRVR+5AA43HkAK5DSntkOCO7nYq5xWAAtIUFRYXWiRjbGFzc25hbWVYJGNsYXNzZXNZRUNLZXlQYWlyohYYWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBXAF0AZAB8AJMAmgC9AOAA4gDnAPIA+wEFAQgAAAAAAAACAQAAAAAAAAAZAAAAAAAAAAAAAAAAAAABEQ=="
        ))
        let decodedKeyPair = try XCTUnwrap(
            NSKeyedUnarchiver.unarchivedObject(ofClass: ECKeyPair.self, from: encodedData, requiringSecureCoding: true)
        )

        XCTAssertEqual(decodedKeyPair.identityKeyPair.privateKey.serialize(), keyPair.identityKeyPair.privateKey.serialize())
        XCTAssertEqual(decodedKeyPair.identityKeyPair.publicKey, keyPair.identityKeyPair.publicKey)
    }

    func testInvalidEncodings() throws {
        let encodedValues = [
            "YnBsaXN0MDDUAQIDBAUGFRZYJHZlcnNpb25YJG9iamVjdHNZJGFyY2hpdmVyVCR0b3ASAAGGoKMHCA9VJG51bGzTCQoLDA0OXxAVVFNFQ0tleVBhaXJQcml2YXRlS2V5XxAUVFNFQ0tleVBhaXJQdWJsaWNLZXlWJGNsYXNzTxAfAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE8QIP0zhOEyrQKlbHj0VUfuQAONx5ACuQ0p7ZDgju52KucVgALSEBESE1gkY2xhc3Nlc1okY2xhc3NuYW1lohMUWUVDS2V5UGFpclhOU09iamVjdF8QD05TS2V5ZWRBcmNoaXZlctEXGFRyb290gAEACAARABoAIwAtADIANwA7AEEASABgAHcAfgCgAMMAxQDKANMA3gDhAOsA9AEGAQkBDgAAAAAAAAIBAAAAAAAAABkAAAAAAAAAAAAAAAAAAAEQ",
            "YnBsaXN0MDDUAQIDBAUGFRZYJHZlcnNpb25YJG9iamVjdHNZJGFyY2hpdmVyVCR0b3ASAAGGoKMHCA9VJG51bGzTCQoLDA0OXxAVVFNFQ0tleVBhaXJQcml2YXRlS2V5XxAUVFNFQ0tleVBhaXJQdWJsaWNLZXlWJGNsYXNzQE8QIP0zhOEyrQKlbHj0VUfuQAONx5ACuQ0p7ZDgju52KucVgALSEBESE1gkY2xhc3Nlc1okY2xhc3NuYW1lohMUWUVDS2V5UGFpclhOU09iamVjdF8QD05TS2V5ZWRBcmNoaXZlctEXGFRyb290gAEIERojLTI3O0FIYHd+f6KkqbK9wMrT5ejtAAAAAAAAAQEAAAAAAAAAGQAAAAAAAAAAAAAAAAAAAO8=",
            "YnBsaXN0MDDUAQIDBAUGExRYJHZlcnNpb25YJG9iamVjdHNZJGFyY2hpdmVyVCR0b3ASAAGGoKMHCA1VJG51bGzSCQoLDF8QFFRTRUNLZXlQYWlyUHVibGljS2V5ViRjbGFzc08QIP0zhOEyrQKlbHj0VUfuQAONx5ACuQ0p7ZDgju52KucVgALSDg8QEVgkY2xhc3Nlc1okY2xhc3NuYW1lohESWUVDS2V5UGFpclhOU09iamVjdF8QD05TS2V5ZWRBcmNoaXZlctEVFlRyb290gAEIERojLTI3O0FGXWSHiY6XoqWvuMrN0gAAAAAAAAEBAAAAAAAAABcAAAAAAAAAAAAAAAAAAADU",
            "YnBsaXN0MDDUAQIDBAUGFRZYJHZlcnNpb25YJG9iamVjdHNZJGFyY2hpdmVyVCR0b3ASAAGGoKMHCA9VJG51bGzTCQoLDA0OXxAVVFNFQ0tleVBhaXJQcml2YXRlS2V5XxAUVFNFQ0tleVBhaXJQdWJsaWNLZXlWJGNsYXNzTxAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEFPEB/9M4ThMq0CpWx49FVH7kADjceQArkNKe2Q4I7udirkgALSEBESE1gkY2xhc3Nlc1okY2xhc3NuYW1lohMUWUVDS2V5UGFpclhOU09iamVjdF8QD05TS2V5ZWRBcmNoaXZlctEXGFRyb290gAEACAARABoAIwAtADIANwA7AEEASABgAHcAfgChAMMAxQDKANMA3gDhAOsA9AEGAQkBDgAAAAAAAAIBAAAAAAAAABkAAAAAAAAAAAAAAAAAAAEQ",
        ]
        for encodedValue in encodedValues {
            let encodedData = try XCTUnwrap(Data(base64Encoded: encodedValue))
            XCTAssertNil(
                try NSKeyedUnarchiver.unarchivedObject(ofClass: ECKeyPair.self, from: encodedData, requiringSecureCoding: true)
            )
        }
    }
}
