// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import SessionUtilitiesKit

import Quick
import Nimble

@testable import SessionMessagingKit

class MessageSenderEncryptionSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        var mockStorage: Storage!
        var mockBox: MockBox!
        var mockSign: MockSign!
        var mockNonce24Generator: MockNonce24Generator!
        var dependencies: SMKDependencies!
        
        describe("a MessageSender") {
            beforeEach {
                mockStorage = Storage(
                    customWriter: try! DatabaseQueue(),
                    customMigrations: [
                        SNUtilitiesKit.migrations(),
                        SNMessagingKit.migrations()
                    ]
                )
                mockBox = MockBox()
                mockSign = MockSign()
                mockNonce24Generator = MockNonce24Generator()
                
                dependencies = SMKDependencies(
                    storage: mockStorage,
                    box: mockBox,
                    sign: mockSign,
                    nonceGenerator24: mockNonce24Generator
                )
                
                mockStorage.write { db in
                    try Identity(variant: .ed25519PublicKey, data: Data(hex: TestConstants.edPublicKey)).insert(db)
                    try Identity(variant: .ed25519SecretKey, data: Data(hex: TestConstants.edSecretKey)).insert(db)
                }
                mockNonce24Generator
                    .when { $0.nonce() }
                    .thenReturn(Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!.bytes)
            }
            
            context("when encrypting with the session protocol") {
                beforeEach {
                    mockBox.when { $0.seal(message: anyArray(), recipientPublicKey: anyArray()) }.thenReturn([1, 2, 3])
                    mockSign.when { $0.signature(message: anyArray(), secretKey: anyArray()) }.thenReturn([])
                }
                
                it("can encrypt correctly") {
                    let result = try? MessageSender.encryptWithSessionProtocol(
                        "TestMessage".data(using: .utf8)!,
                        for: "05\(TestConstants.publicKey)",
                        using: SMKDependencies(storage: mockStorage)
                    )
                    
                    // Note: A Nonce is used for this so we can't compare the exact value when not mocked
                    expect(result).toNot(beNil())
                    expect(result?.count).to(equal(155))
                }
                
                it("returns the correct value when mocked") {
                    let result = try? MessageSender.encryptWithSessionProtocol(
                        "TestMessage".data(using: .utf8)!,
                        for: "05\(TestConstants.publicKey)",
                        using: dependencies
                    )
                    
                    expect(result?.bytes).to(equal([1, 2, 3]))
                }
                
                it("throws an error if there is no ed25519 keyPair") {
                    mockStorage.write { db in
                        _ = try Identity.filter(id: .ed25519PublicKey).deleteAll(db)
                        _ = try Identity.filter(id: .ed25519SecretKey).deleteAll(db)
                    }
                    
                    expect {
                        try MessageSender.encryptWithSessionProtocol(
                            "TestMessage".data(using: .utf8)!,
                            for: "05\(TestConstants.publicKey)",
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageSenderError.noUserED25519KeyPair))
                }
                
                it("throws an error if the signature generation fails") {
                    mockSign.when { $0.signature(message: anyArray(), secretKey: anyArray()) }.thenReturn(nil)
                    
                    expect {
                        try MessageSender.encryptWithSessionProtocol(
                            "TestMessage".data(using: .utf8)!,
                            for: "05\(TestConstants.publicKey)",
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageSenderError.signingFailed))
                }
                
                it("throws an error if the encryption fails") {
                    mockBox.when { $0.seal(message: anyArray(), recipientPublicKey: anyArray()) }.thenReturn(nil)
                    
                    expect {
                        try MessageSender.encryptWithSessionProtocol(
                            "TestMessage".data(using: .utf8)!,
                            for: "05\(TestConstants.publicKey)",
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageSenderError.encryptionFailed))
                }
            }
            
            context("when encrypting with the blinded session protocol") {
                it("successfully encrypts") {
                    let result = try? MessageSender.encryptWithSessionBlindingProtocol(
                        "TestMessage".data(using: .utf8)!,
                        for: "15\(TestConstants.blindedPublicKey)",
                        openGroupPublicKey: TestConstants.serverPublicKey,
                        using: dependencies
                    )
                    
                    expect(result?.toHexString())
                        .to(equal(
                            "00db16b6687382811d69875a5376f66acad9c49fe5e26bcf770c7e6e9c230299" +
                            "f61b315299dd1fa700dd7f34305c0465af9e64dc791d7f4123f1eeafa5b4d48b" +
                            "3ade4f4b2a2764762e5a2c7900f254bd91633b43"
                        ))
                }
                
                it("includes a version at the start of the encrypted value") {
                    let result = try? MessageSender.encryptWithSessionBlindingProtocol(
                        "TestMessage".data(using: .utf8)!,
                        for: "15\(TestConstants.blindedPublicKey)",
                        openGroupPublicKey: TestConstants.serverPublicKey,
                        using: dependencies
                    )
                    
                    expect(result?.toHexString().prefix(2)).to(equal("00"))
                }
                
                it("includes the nonce at the end of the encrypted value") {
                    let maybeResult = try? MessageSender.encryptWithSessionBlindingProtocol(
                        "TestMessage".data(using: .utf8)!,
                        for: "15\(TestConstants.blindedPublicKey)",
                        openGroupPublicKey: TestConstants.serverPublicKey,
                        using: dependencies
                    )
                    let result: [UInt8] = (maybeResult?.bytes ?? [])
                    let nonceBytes: [UInt8] = Array(result[max(0, (result.count - 24))..<result.count])
                    
                    expect(Data(nonceBytes).base64EncodedString())
                        .to(equal("pbTUizreT0sqJ2R2LloseQDyVL2RYztD"))
                }
                
                it("throws an error if the recipient isn't a blinded id") {
                    expect {
                        try MessageSender.encryptWithSessionBlindingProtocol(
                            "TestMessage".data(using: .utf8)!,
                            for: "05\(TestConstants.publicKey)",
                            openGroupPublicKey: TestConstants.serverPublicKey,
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageSenderError.signingFailed))
                }
                
                it("throws an error if there is no ed25519 keyPair") {
                    mockStorage.write { db in
                        _ = try Identity.filter(id: .ed25519PublicKey).deleteAll(db)
                        _ = try Identity.filter(id: .ed25519SecretKey).deleteAll(db)
                    }
                    
                    expect {
                        try MessageSender.encryptWithSessionBlindingProtocol(
                            "TestMessage".data(using: .utf8)!,
                            for: "15\(TestConstants.blindedPublicKey)",
                            openGroupPublicKey: TestConstants.serverPublicKey,
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageSenderError.noUserED25519KeyPair))
                }
                
                it("throws an error if it fails to generate a blinded keyPair") {
                    let mockSodium: MockSodium = MockSodium()
                    let mockGenericHash: MockGenericHash = MockGenericHash()
                    dependencies = dependencies.with(sodium: mockSodium, genericHash: mockGenericHash)
                    
                    mockSodium
                        .when {
                            $0.blindedKeyPair(
                                serverPublicKey: any(),
                                edKeyPair: any(),
                                genericHash: mockGenericHash
                            )
                        }
                        .thenReturn(nil)
                    
                    expect {
                        try MessageSender.encryptWithSessionBlindingProtocol(
                            "TestMessage".data(using: .utf8)!,
                            for: "15\(TestConstants.blindedPublicKey)",
                            openGroupPublicKey: TestConstants.serverPublicKey,
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageSenderError.signingFailed))
                }
                
                it("throws an error if it fails to generate an encryption key") {
                    let mockSodium: MockSodium = MockSodium()
                    let mockGenericHash: MockGenericHash = MockGenericHash()
                    dependencies = dependencies.with(sodium: mockSodium, genericHash: mockGenericHash)
                    
                    mockSodium
                        .when {
                            $0.blindedKeyPair(
                                serverPublicKey: any(),
                                edKeyPair: any(),
                                genericHash: mockGenericHash
                            )
                        }
                        .thenReturn(
                            Box.KeyPair(
                                publicKey: Data(hex: TestConstants.edPublicKey).bytes,
                                secretKey: Data(hex: TestConstants.edSecretKey).bytes
                            )
                        )
                    mockSodium
                        .when {
                            $0.sharedBlindedEncryptionKey(
                                secretKey: anyArray(),
                                otherBlindedPublicKey: anyArray(),
                                fromBlindedPublicKey: anyArray(),
                                toBlindedPublicKey: anyArray(),
                                genericHash: mockGenericHash
                            )
                        }
                        .thenReturn(nil)
                    
                    expect {
                        try MessageSender.encryptWithSessionBlindingProtocol(
                            "TestMessage".data(using: .utf8)!,
                            for: "15\(TestConstants.blindedPublicKey)",
                            openGroupPublicKey: TestConstants.serverPublicKey,
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageSenderError.signingFailed))
                }
                
                it("throws an error if it fails to encrypt") {
                    let mockAeadXChaCha: MockAeadXChaCha20Poly1305Ietf = MockAeadXChaCha20Poly1305Ietf()
                    dependencies = dependencies.with(aeadXChaCha20Poly1305Ietf: mockAeadXChaCha)
                    
                    mockAeadXChaCha
                        .when { $0.encrypt(message: anyArray(), secretKey: anyArray(), nonce: anyArray()) }
                        .thenReturn(nil)
                    
                    expect {
                        try MessageSender.encryptWithSessionBlindingProtocol(
                            "TestMessage".data(using: .utf8)!,
                            for: "15\(TestConstants.blindedPublicKey)",
                            openGroupPublicKey: TestConstants.serverPublicKey,
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageSenderError.encryptionFailed))
                }
            }
        }
    }
}
