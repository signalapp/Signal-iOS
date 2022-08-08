// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium

import Quick
import Nimble

@testable import SessionMessagingKit

class SodiumUtilitiesSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        // MARK: - Sign
        
        describe("an extended Sign") {
            var sign: Sign!
            
            beforeEach {
                sign = Sodium().sign
            }
            
            it("can convert an ed25519 public key into an x25519 public key") {
                let result = sign.toX25519(ed25519PublicKey: TestConstants.edPublicKey.bytes)
                
                expect(result?.toHexString())
                    .to(equal("95ffb559d4e804e9b414a5178454c426f616b4a61089b217b41165dbb7c9fe2d"))
            }
            
            it("can convert an ed25519 private key into an x25519 private key") {
                let result = sign.toX25519(ed25519SecretKey: TestConstants.edSecretKey.bytes)
                
                expect(result?.toHexString())
                    .to(equal("c83f9a1479b103c275d2db2d6c199fdc6f589b29b742f6405e01cc5a9a1d135d"))
            }
        }
        
        // MARK: - Sodium
        
        describe("an extended Sodium") {
            var sodium: Sodium!
            var genericHash: GenericHashType!
            
            beforeEach {
                sodium = Sodium()
                genericHash = sodium.genericHash
            }
            
            context("when generating a blinding factor") {
                it("successfully generates a blinding factor") {
                    let result = sodium.generateBlindingFactor(
                        serverPublicKey: TestConstants.serverPublicKey,
                        genericHash: genericHash
                    )
                    
                    expect(result?.toHexString())
                        .to(equal("84e3eb75028a9b73fec031b7448e322a68ca6485fad81ab1bead56f759ebeb0f"))
                }
                
                it("fails if the serverPublicKey is not a hex string") {
                    let result = sodium.generateBlindingFactor(
                        serverPublicKey: "Test",
                        genericHash: genericHash
                    )
                    
                    expect(result).to(beNil())
                }
                
                it("fails if it cannot hash the serverPublicKey bytes") {
                    genericHash = MockGenericHash()
                    (genericHash as? MockGenericHash)?
                        .when { $0.hash(message: anyArray(), outputLength: any()) }
                        .thenReturn(nil)
                    
                    let result = sodium.generateBlindingFactor(
                        serverPublicKey: TestConstants.serverPublicKey,
                        genericHash: genericHash
                    )
                    
                    expect(result).to(beNil())
                }
            }
            
            context("when generating a blinded key pair") {
                it("successfully generates a blinded key pair") {
                    let result = sodium.blindedKeyPair(
                        serverPublicKey: TestConstants.serverPublicKey,
                        edKeyPair: Box.KeyPair(
                            publicKey: Data(hex: TestConstants.edPublicKey).bytes,
                            secretKey: Data(hex: TestConstants.edSecretKey).bytes
                        ),
                        genericHash: genericHash
                    )
                    
                    // Note: The first 64 characters of the secretKey are consistent but the chars after that always differ
                    expect(result?.publicKey.toHexString()).to(equal(TestConstants.blindedPublicKey))
                    expect(String(result?.secretKey.toHexString().prefix(64) ?? ""))
                        .to(equal("16663322d6b684e1c9dcc02b9e8642c3affd3bc431a9ea9e63dbbac88ce7a305"))
                }
                
                it("fails if the edKeyPair public key length wrong") {
                    let result = sodium.blindedKeyPair(
                        serverPublicKey: TestConstants.serverPublicKey,
                        edKeyPair: Box.KeyPair(
                            publicKey: Data(hex: String(TestConstants.edPublicKey.prefix(4))).bytes,
                            secretKey: Data(hex: TestConstants.edSecretKey).bytes
                        ),
                        genericHash: genericHash
                    )
                    
                    expect(result).to(beNil())
                }
                
                it("fails if the edKeyPair secret key length wrong") {
                    let result = sodium.blindedKeyPair(
                        serverPublicKey: TestConstants.serverPublicKey,
                        edKeyPair: Box.KeyPair(
                            publicKey: Data(hex: TestConstants.edPublicKey).bytes,
                            secretKey: Data(hex: String(TestConstants.edSecretKey.prefix(4))).bytes
                        ),
                        genericHash: genericHash
                    )
                    
                    expect(result).to(beNil())
                }
                
                it("fails if it cannot generate a blinding factor") {
                    let result = sodium.blindedKeyPair(
                        serverPublicKey: "Test",
                        edKeyPair: Box.KeyPair(
                            publicKey: Data(hex: TestConstants.edPublicKey).bytes,
                            secretKey: Data(hex: TestConstants.edSecretKey).bytes
                        ),
                        genericHash: genericHash
                    )
                    
                    expect(result).to(beNil())
                }
            }
            
            context("when generating a sogsSignature") {
                it("generates a correct signature") {
                    let result = sodium.sogsSignature(
                        message: "TestMessage".bytes,
                        secretKey: Data(hex: TestConstants.edSecretKey).bytes,
                        blindedSecretKey: Data(hex: "44d82cc15c0a5056825cae7520b6b52d000a23eb0c5ed94c4be2d9dc41d2d409").bytes,
                        blindedPublicKey: Data(hex: "0bb7815abb6ba5142865895f3e5286c0527ba4d31dbb75c53ce95e91ffe025a2").bytes
                    )
                    
                    expect(result?.toHexString())
                        .to(equal(
                            "dcc086abdd2a740d9260b008fb37e12aa0ff47bd2bd9e177bbbec37fd46705a9" +
                            "072ce747bda66c788c3775cdd7ad60ad15a478e0886779aad5d795fd7bf8350d"
                        ))
                }
            }
            
            context("when combining keys") {
                it("generates a correct combined key") {
                    let result = sodium.combineKeys(
                        lhsKeyBytes: Data(hex: TestConstants.edSecretKey).bytes,
                        rhsKeyBytes: Data(hex: TestConstants.edPublicKey).bytes
                    )
                    
                    expect(result?.toHexString())
                        .to(equal("1159b5d0fcfba21228eb2121a0f59712fa8276fc6e5547ff519685a40b9819e6"))
                }
                
                it("fails if the scalar multiplication fails") {
                    let result = sodium.combineKeys(
                        lhsKeyBytes: sodium.generatePrivateKeyScalar(secretKey: Data(hex: TestConstants.edSecretKey).bytes),
                        rhsKeyBytes: Data(hex: TestConstants.publicKey).bytes
                    )
                    
                    expect(result).to(beNil())
                }
            }
            
            context("when creating a shared blinded encryption key") {
                it("generates a correct combined key") {
                    let result = sodium.sharedBlindedEncryptionKey(
                        secretKey: Data(hex: TestConstants.edSecretKey).bytes,
                        otherBlindedPublicKey: Data(hex: TestConstants.blindedPublicKey).bytes,
                        fromBlindedPublicKey: Data(hex: TestConstants.publicKey).bytes,
                        toBlindedPublicKey: Data(hex: TestConstants.blindedPublicKey).bytes,
                        genericHash: genericHash
                    )
                    
                    expect(result?.toHexString())
                        .to(equal("388ee09e4c356b91f1cce5cc0aa0cf59e8e8cade69af61685d09c2d2731bc99e"))
                }
                
                it("fails if the scalar multiplication fails") {
                    let result = sodium.sharedBlindedEncryptionKey(
                        secretKey: Data(hex: TestConstants.edSecretKey).bytes,
                        otherBlindedPublicKey: Data(hex: TestConstants.publicKey).bytes,
                        fromBlindedPublicKey: Data(hex: TestConstants.edPublicKey).bytes,
                        toBlindedPublicKey: Data(hex: TestConstants.publicKey).bytes,
                        genericHash: genericHash
                    )
                    
                    expect(result?.toHexString()).to(beNil())
                }
            }
            
            context("when checking if a session id matches a blinded id") {
                it("returns true when they match") {
                    let result = sodium.sessionId(
                        "05\(TestConstants.publicKey)",
                        matchesBlindedId: "15\(TestConstants.blindedPublicKey)",
                        serverPublicKey: TestConstants.serverPublicKey,
                        genericHash: genericHash
                    )
                    
                    expect(result).to(beTrue())
                }
                
                it("returns false if given an invalid session id") {
                    let result = sodium.sessionId(
                        "AB\(TestConstants.publicKey)",
                        matchesBlindedId: "15\(TestConstants.blindedPublicKey)",
                        serverPublicKey: TestConstants.serverPublicKey,
                        genericHash: genericHash
                    )
                    
                    expect(result).to(beFalse())
                }
                
                it("returns false if given an invalid blinded id") {
                    let result = sodium.sessionId(
                        "05\(TestConstants.publicKey)",
                        matchesBlindedId: "AB\(TestConstants.blindedPublicKey)",
                        serverPublicKey: TestConstants.serverPublicKey,
                        genericHash: genericHash
                    )
                    
                    expect(result).to(beFalse())
                }
                
                it("returns false if it fails to generate the blinding factor") {
                    let result = sodium.sessionId(
                        "05\(TestConstants.publicKey)",
                        matchesBlindedId: "15\(TestConstants.blindedPublicKey)",
                        serverPublicKey: "Test",
                        genericHash: genericHash
                    )
                    
                    expect(result).to(beFalse())
                }
            }
        }
        
        // MARK: - GenericHash
        
        describe("an extended GenericHash") {
            var genericHash: GenericHashType!
            
            beforeEach {
                genericHash = Sodium().genericHash
            }
            
            context("when generating a hash with salt and personal values") {
                it("generates a hash correctly") {
                    let result = genericHash.hashSaltPersonal(
                        message: "TestMessage".bytes,
                        outputLength: 32,
                        key: "Key".bytes,
                        salt: "Salt".bytes,
                        personal: "Personal".bytes
                    )
                    
                    expect(result).toNot(beNil())
                    expect(result?.count).to(equal(32))
                }
                
                it("generates a hash correctly with no key") {
                    let result = genericHash.hashSaltPersonal(
                        message: "TestMessage".bytes,
                        outputLength: 32,
                        key: nil,
                        salt: "Salt".bytes,
                        personal: "Personal".bytes
                    )
                    
                    expect(result).toNot(beNil())
                    expect(result?.count).to(equal(32))
                }
                
                it("fails if given invalid options") {
                    let result = genericHash.hashSaltPersonal(
                        message: "TestMessage".bytes,
                        outputLength: 65,   // Max of 64
                        key: "Key".bytes,
                        salt: "Salt".bytes,
                        personal: "Personal".bytes
                    )
                    
                    expect(result).to(beNil())
                }
            }
        }
        
        // MARK: - AeadXChaCha20Poly1305IetfType
        
        describe("an extended AeadXChaCha20Poly1305IetfType") {
            var aeadXchacha20poly1305ietf: AeadXChaCha20Poly1305IetfType!
            
            beforeEach {
                aeadXchacha20poly1305ietf = Sodium().aead.xchacha20poly1305ietf
            }
            
            context("when encrypting") {
                it("encrypts correctly") {
                    let result = aeadXchacha20poly1305ietf.encrypt(
                        message: "TestMessage".bytes,
                        secretKey: Data(hex: TestConstants.publicKey).bytes,
                        nonce: "TestNonce".bytes,
                        additionalData: nil
                    )
                    
                    expect(result).toNot(beNil())
                    expect(result?.count).to(equal(27))
                }
                
                it("encrypts correctly with additional data") {
                    let result = aeadXchacha20poly1305ietf.encrypt(
                        message: "TestMessage".bytes,
                        secretKey: Data(hex: TestConstants.publicKey).bytes,
                        nonce: "TestNonce".bytes,
                        additionalData: "TestData".bytes
                    )
                    
                    expect(result).toNot(beNil())
                    expect(result?.count).to(equal(27))
                }
                
                it("fails if given an invalid key") {
                    let result = aeadXchacha20poly1305ietf.encrypt(
                        message: "TestMessage".bytes,
                        secretKey: "TestKey".bytes,
                        nonce: "TestNonce".bytes,
                        additionalData: "TestData".bytes
                    )
                    
                    expect(result).to(beNil())
                }
            }
        }
    }
}
