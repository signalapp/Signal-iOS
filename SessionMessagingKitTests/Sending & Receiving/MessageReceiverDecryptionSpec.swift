// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import GRDB
import SessionUtilitiesKit

import Quick
import Nimble

@testable import SessionMessagingKit

class MessageReceiverDecryptionSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        var mockStorage: Storage!
        var mockSodium: MockSodium!
        var mockBox: MockBox!
        var mockGenericHash: MockGenericHash!
        var mockSign: MockSign!
        var mockAeadXChaCha: MockAeadXChaCha20Poly1305Ietf!
        var mockNonce24Generator: MockNonce24Generator!
        var dependencies: SMKDependencies!
        
        describe("a MessageReceiver") {
            beforeEach {
                mockStorage = Storage(
                    customWriter: try! DatabaseQueue(),
                    customMigrations: [
                        SNUtilitiesKit.migrations(),
                        SNMessagingKit.migrations()
                    ]
                )
                mockSodium = MockSodium()
                mockBox = MockBox()
                mockGenericHash = MockGenericHash()
                mockSign = MockSign()
                mockAeadXChaCha = MockAeadXChaCha20Poly1305Ietf()
                mockNonce24Generator = MockNonce24Generator()
                
                mockAeadXChaCha
                    .when { $0.encrypt(message: anyArray(), secretKey: anyArray(), nonce: anyArray()) }
                    .thenReturn(nil)
                
                dependencies = SMKDependencies(
                    storage: mockStorage,
                    sodium: mockSodium,
                    box: mockBox,
                    genericHash: mockGenericHash,
                    sign: mockSign,
                    aeadXChaCha20Poly1305Ietf: mockAeadXChaCha,
                    nonceGenerator24: mockNonce24Generator
                )
                
                mockStorage.write { db in
                    try Identity(variant: .ed25519PublicKey, data: Data(hex: TestConstants.edPublicKey)).insert(db)
                    try Identity(variant: .ed25519SecretKey, data: Data(hex: TestConstants.edSecretKey)).insert(db)
                }
                mockBox
                    .when {
                        $0.open(
                            anonymousCipherText: anyArray(),
                            recipientPublicKey: anyArray(),
                            recipientSecretKey: anyArray()
                        )
                    }
                    .thenReturn([UInt8](repeating: 0, count: 100))
                mockSodium
                    .when { $0.blindedKeyPair(serverPublicKey: any(), edKeyPair: any(), genericHash: mockGenericHash) }
                    .thenReturn(
                        Box.KeyPair(
                            publicKey: Data(hex: TestConstants.blindedPublicKey).bytes,
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
                    .thenReturn([])
                mockSodium
                    .when { $0.generateBlindingFactor(serverPublicKey: any(), genericHash: mockGenericHash) }
                    .thenReturn([])
                mockSodium
                    .when { $0.combineKeys(lhsKeyBytes: anyArray(), rhsKeyBytes: anyArray()) }
                    .thenReturn(Data(hex: TestConstants.blindedPublicKey).bytes)
                mockSign
                    .when { $0.toX25519(ed25519PublicKey: anyArray()) }
                    .thenReturn(Data(hex: TestConstants.publicKey).bytes)
                mockSign
                    .when { $0.verify(message: anyArray(), publicKey: anyArray(), signature: anyArray()) }
                    .thenReturn(true)
                mockAeadXChaCha
                    .when { $0.decrypt(authenticatedCipherText: anyArray(), secretKey: anyArray(), nonce: anyArray()) }
                    .thenReturn("TestMessage".data(using: .utf8)!.bytes + [UInt8](repeating: 0, count: 32))
                mockNonce24Generator
                    .when { $0.nonce() }
                    .thenReturn(Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!.bytes)
            }
            
            context("when decrypting with the session protocol") {
                it("successfully decrypts a message") {
                    let result = try? MessageReceiver.decryptWithSessionProtocol(
                        ciphertext: Data(
                            base64Encoded: "SRP0eBUWh4ez6ppWjUs5/Wph5fhnPRgB5zsWWnTz+FBAw/YI3oS2pDpIfyetMTbU" +
                            "sFMhE5G4PbRtQFey1hsxLl221Qivc3ayaX2Mm/X89Dl8e45BC+Lb/KU9EdesxIK4pVgYXs9XrMtX3v8" +
                            "dt0eBaXneOBfr7qB8pHwwMZjtkOu1ED07T9nszgbWabBphUfWXe2U9K3PTRisSCI="
                        )!,
                        using: Box.KeyPair(
                            publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
                            secretKey: Data.data(fromHex: TestConstants.privateKey)!.bytes
                        ),
                        dependencies: SMKDependencies()
                    )
                    
                    expect(String(data: (result?.plaintext ?? Data()), encoding: .utf8)).to(equal("TestMessage"))
                    expect(result?.senderX25519PublicKey)
                        .to(equal("0588672ccb97f40bb57238989226cf429b575ba355443f47bc76c5ab144a96c65b"))
                }
                
                it("throws an error if it cannot open the message") {
                    mockBox
                        .when {
                            $0.open(
                                anonymousCipherText: anyArray(),
                                recipientPublicKey: anyArray(),
                                recipientSecretKey: anyArray()
                            )
                        }
                        .thenReturn(nil)
                    
                    expect {
                        try MessageReceiver.decryptWithSessionProtocol(
                            ciphertext: "TestMessage".data(using: .utf8)!,
                            using: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.privateKey)!.bytes
                            ),
                            dependencies: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.decryptionFailed))
                }
                
                it("throws an error if the open message is too short") {
                    mockBox
                        .when {
                            $0.open(
                                anonymousCipherText: anyArray(),
                                recipientPublicKey: anyArray(),
                                recipientSecretKey: anyArray()
                            )
                        }
                        .thenReturn([1, 2, 3])
                    
                    expect {
                        try MessageReceiver.decryptWithSessionProtocol(
                            ciphertext: "TestMessage".data(using: .utf8)!,
                            using: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.privateKey)!.bytes
                            ),
                            dependencies: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.decryptionFailed))
                }
                
                it("throws an error if it cannot verify the message") {
                    mockSign
                        .when { $0.verify(message: anyArray(), publicKey: anyArray(), signature: anyArray()) }
                        .thenReturn(false)
                    
                    expect {
                        try MessageReceiver.decryptWithSessionProtocol(
                            ciphertext: "TestMessage".data(using: .utf8)!,
                            using: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.privateKey)!.bytes
                            ),
                            dependencies: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.invalidSignature))
                }
                
                it("throws an error if it cannot get the senders x25519 public key") {
                    mockSign.when { $0.toX25519(ed25519PublicKey: anyArray()) }.thenReturn(nil)
                    
                    expect {
                        try MessageReceiver.decryptWithSessionProtocol(
                            ciphertext: "TestMessage".data(using: .utf8)!,
                            using: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.privateKey)!.bytes
                            ),
                            dependencies: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.decryptionFailed))
                }
            }
            
            context("when decrypting with the blinded session protocol") {
                it("successfully decrypts a message") {
                    let result = try? MessageReceiver.decryptWithSessionBlindingProtocol(
                        data: Data(
                            hex: "00db16b6687382811d69875a5376f66acad9c49fe5e26bcf770c7e6e9c230299" +
                            "f61b315299dd1fa700dd7f34305c0465af9e64dc791d7f4123f1eeafa5b4d48b3ade4" +
                            "f4b2a2764762e5a2c7900f254bd91633b43"
                        ),
                        isOutgoing: true,
                        otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                        with: TestConstants.serverPublicKey,
                        userEd25519KeyPair: Box.KeyPair(
                            publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                            secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                        ),
                        using: SMKDependencies()
                    )
                    
                    expect(String(data: (result?.plaintext ?? Data()), encoding: .utf8)).to(equal("TestMessage"))
                    expect(result?.senderX25519PublicKey)
                        .to(equal("0588672ccb97f40bb57238989226cf429b575ba355443f47bc76c5ab144a96c65b"))
                }
                
                it("successfully decrypts a mocked incoming message") {
                    let result = try? MessageReceiver.decryptWithSessionBlindingProtocol(
                        data: (
                            Data([0]) +
                            "TestMessage".data(using: .utf8)! +
                            Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!
                        ),
                        isOutgoing: false,
                        otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                        with: TestConstants.serverPublicKey,
                        userEd25519KeyPair: Box.KeyPair(
                            publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                            secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                        ),
                        using: dependencies
                    )
                    
                    expect(String(data: (result?.plaintext ?? Data()), encoding: .utf8)).to(equal("TestMessage"))
                    expect(result?.senderX25519PublicKey)
                        .to(equal("0588672ccb97f40bb57238989226cf429b575ba355443f47bc76c5ab144a96c65b"))
                }
                
                it("throws an error if the data is too short") {
                    expect {
                        try MessageReceiver.decryptWithSessionBlindingProtocol(
                            data: Data([1, 2, 3]),
                            isOutgoing: true,
                            otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                            with: TestConstants.serverPublicKey,
                            userEd25519KeyPair: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                            ),
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.decryptionFailed))
                }
                
                it("throws an error if it cannot get the blinded keyPair") {
                    mockSodium
                        .when { $0.blindedKeyPair(serverPublicKey: any(), edKeyPair: any(), genericHash: mockGenericHash) }
                        .thenReturn(nil)
                    
                    expect {
                        try MessageReceiver.decryptWithSessionBlindingProtocol(
                            data: (
                                Data([0]) +
                                "TestMessage".data(using: .utf8)! +
                                Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!
                            ),
                            isOutgoing: true,
                            otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                            with: TestConstants.serverPublicKey,
                            userEd25519KeyPair: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                            ),
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.decryptionFailed))
                }
                
                it("throws an error if it cannot get the decryption key") {
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
                        try MessageReceiver.decryptWithSessionBlindingProtocol(
                            data: (
                                Data([0]) +
                                "TestMessage".data(using: .utf8)! +
                                Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!
                            ),
                            isOutgoing: true,
                            otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                            with: TestConstants.serverPublicKey,
                            userEd25519KeyPair: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                            ),
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.decryptionFailed))
                }
                
                it("throws an error if the data version is not 0") {
                    expect {
                        try MessageReceiver.decryptWithSessionBlindingProtocol(
                            data: (
                                Data([1]) +
                                "TestMessage".data(using: .utf8)! +
                                Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!
                            ),
                            isOutgoing: true,
                            otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                            with: TestConstants.serverPublicKey,
                            userEd25519KeyPair: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                            ),
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.decryptionFailed))
                }
                
                it("throws an error if it cannot decrypt the data") {
                    mockAeadXChaCha
                        .when { $0.decrypt(authenticatedCipherText: anyArray(), secretKey: anyArray(), nonce: anyArray()) }
                        .thenReturn(nil)
                    
                    expect {
                        try MessageReceiver.decryptWithSessionBlindingProtocol(
                            data: (
                                Data([0]) +
                                "TestMessage".data(using: .utf8)! +
                                Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!
                            ),
                            isOutgoing: true,
                            otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                            with: TestConstants.serverPublicKey,
                            userEd25519KeyPair: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                            ),
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.decryptionFailed))
                }
                
                it("throws an error if the inner bytes are too short") {
                    mockAeadXChaCha
                        .when { $0.decrypt(authenticatedCipherText: anyArray(), secretKey: anyArray(), nonce: anyArray()) }
                        .thenReturn([1, 2, 3])
                    
                    expect {
                        try MessageReceiver.decryptWithSessionBlindingProtocol(
                            data: (
                                Data([0]) +
                                "TestMessage".data(using: .utf8)! +
                                Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!
                            ),
                            isOutgoing: true,
                            otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                            with: TestConstants.serverPublicKey,
                            userEd25519KeyPair: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                            ),
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.decryptionFailed))
                }
                
                it("throws an error if it cannot generate the blinding factor") {
                    mockSodium
                        .when { $0.generateBlindingFactor(serverPublicKey: any(), genericHash: mockGenericHash) }
                        .thenReturn(nil)
                    
                    expect {
                        try MessageReceiver.decryptWithSessionBlindingProtocol(
                            data: (
                                Data([0]) +
                                "TestMessage".data(using: .utf8)! +
                                Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!
                            ),
                            isOutgoing: true,
                            otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                            with: TestConstants.serverPublicKey,
                            userEd25519KeyPair: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                            ),
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.invalidSignature))
                }
                
                it("throws an error if it cannot generate the combined key") {
                    mockSodium
                        .when { $0.combineKeys(lhsKeyBytes: anyArray(), rhsKeyBytes: anyArray()) }
                        .thenReturn(nil)
                    
                    expect {
                        try MessageReceiver.decryptWithSessionBlindingProtocol(
                            data: (
                                Data([0]) +
                                "TestMessage".data(using: .utf8)! +
                                Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!
                            ),
                            isOutgoing: true,
                            otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                            with: TestConstants.serverPublicKey,
                            userEd25519KeyPair: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                            ),
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.invalidSignature))
                }
                
                it("throws an error if the combined key does not match kA") {
                    mockSodium
                        .when { $0.combineKeys(lhsKeyBytes: anyArray(), rhsKeyBytes: anyArray()) }
                        .thenReturn(Data(hex: TestConstants.publicKey).bytes)
                    
                    expect {
                        try MessageReceiver.decryptWithSessionBlindingProtocol(
                            data: (
                                Data([0]) +
                                "TestMessage".data(using: .utf8)! +
                                Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!
                            ),
                            isOutgoing: true,
                            otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                            with: TestConstants.serverPublicKey,
                            userEd25519KeyPair: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                            ),
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.invalidSignature))
                }
                
                it("throws an error if it cannot get the senders x25519 public key") {
                    mockSign
                        .when { $0.toX25519(ed25519PublicKey: anyArray()) }
                        .thenReturn(nil)
                    
                    expect {
                        try MessageReceiver.decryptWithSessionBlindingProtocol(
                            data: (
                                Data([0]) +
                                "TestMessage".data(using: .utf8)! +
                                Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!
                            ),
                            isOutgoing: true,
                            otherBlindedPublicKey: "15\(TestConstants.blindedPublicKey)",
                            with: TestConstants.serverPublicKey,
                            userEd25519KeyPair: Box.KeyPair(
                                publicKey: Data.data(fromHex: TestConstants.edPublicKey)!.bytes,
                                secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                            ),
                            using: dependencies
                        )
                    }
                    .to(throwError(MessageReceiverError.decryptionFailed))
                }
            }
        }
    }
}
