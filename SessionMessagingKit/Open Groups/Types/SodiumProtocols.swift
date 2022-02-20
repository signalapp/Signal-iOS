// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import Curve25519Kit

public protocol SodiumType {
    func getGenericHash() -> GenericHashType
    func getAeadXChaCha20Poly1305Ietf() -> AeadXChaCha20Poly1305IetfType
    func getSign() -> SignType
    
    func blindedKeyPair(serverPublicKey: String, edKeyPair: Box.KeyPair, genericHash: GenericHashType) -> Box.KeyPair?
    func sogsSignature(message: Bytes, secretKey: Bytes, blindedSecretKey ka: Bytes, blindedPublicKey kA: Bytes) -> Bytes?
    
    func sharedEdSecret(_ firstKeyBytes: [UInt8], _ secondKeyBytes: [UInt8]) -> Bytes?
}

public protocol AeadXChaCha20Poly1305IetfType {
    func encrypt(message: Bytes, secretKey: Aead.XChaCha20Poly1305Ietf.Key, additionalData: Bytes?) -> (authenticatedCipherText: Bytes, nonce: Aead.XChaCha20Poly1305Ietf.Nonce)?
}

public protocol Ed25519Type {
    static func verifySignature(_ signature: Data, publicKey: Data, data: Data) throws -> Bool
}

public protocol SignType {
    func signature(message: Bytes, secretKey: Bytes) -> Bytes?
    func verify(message: Bytes, publicKey: Bytes, signature: Bytes) -> Bool
}

public protocol GenericHashType {
    func hash(message: Bytes, key: Bytes?) -> Bytes?
    func hash(message: Bytes, outputLength: Int) -> Bytes?
    func hashSaltPersonal(message: Bytes, outputLength: Int, key: Bytes?, salt: Bytes, personal: Bytes) -> Bytes?
}

// MARK: - Default Values

extension AeadXChaCha20Poly1305IetfType {
    func encrypt(message: Bytes, secretKey: Aead.XChaCha20Poly1305Ietf.Key) -> (authenticatedCipherText: Bytes, nonce: Aead.XChaCha20Poly1305Ietf.Nonce)? {
        return encrypt(message: message, secretKey: secretKey, additionalData: nil)
    }
}

extension GenericHashType {
    func hash(message: Bytes) -> Bytes? { return hash(message: message, key: nil) }
    
    func hashSaltPersonal(message: Bytes, outputLength: Int, salt: Bytes, personal: Bytes) -> Bytes? {
        return hashSaltPersonal(message: message, outputLength: outputLength, key: nil, salt: salt, personal: personal)
    }
}

// MARK: - Conformance

extension Sodium: SodiumType {
    public func getGenericHash() -> GenericHashType { return genericHash }
    public func getSign() -> SignType { return sign }
    public func getAeadXChaCha20Poly1305Ietf() -> AeadXChaCha20Poly1305IetfType { return aead.xchacha20poly1305ietf }
    
    public func blindedKeyPair(serverPublicKey: String, edKeyPair: Box.KeyPair) -> Box.KeyPair? {
        return blindedKeyPair(serverPublicKey: serverPublicKey, edKeyPair: edKeyPair, genericHash: getGenericHash())
    }
}

extension Aead.XChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType {}
extension Sign: SignType {}
extension GenericHash: GenericHashType {}
extension Ed25519: Ed25519Type {}
