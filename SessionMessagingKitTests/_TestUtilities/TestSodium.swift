// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class TestSodium: SodiumType, Mockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case genericHash
        case aeadXChaCha20Poly1305Ietf
        case sign
        case blindingFactor
        case blindedKeyPair
        case sogsSignature
        case combinedKeys
        case sharedBlindedEncryptionKey
        case sessionIdMatches
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    
    // MARK: - SodiumType
    
    func getGenericHash() -> GenericHashType { return (mockData[.genericHash] as! GenericHashType) }
    
    func getAeadXChaCha20Poly1305Ietf() -> AeadXChaCha20Poly1305IetfType {
        return (mockData[.aeadXChaCha20Poly1305Ietf] as! AeadXChaCha20Poly1305IetfType)
    }
    
    func getSign() -> SignType { return (mockData[.sign] as! SignType) }
    
    func generateBlindingFactor(serverPublicKey: String) -> Bytes? { return (mockData[.blindingFactor] as? Bytes) }
    
    func blindedKeyPair(serverPublicKey: String, edKeyPair: Box.KeyPair, genericHash: GenericHashType) -> Box.KeyPair? {
        return (mockData[.blindedKeyPair] as? Box.KeyPair)
    }
    
    func sogsSignature(message: Bytes, secretKey: Bytes, blindedSecretKey ka: Bytes, blindedPublicKey kA: Bytes) -> Bytes? {
        return (mockData[.sogsSignature] as? Bytes)
    }
    
    func combineKeys(lhsKeyBytes: Bytes, rhsKeyBytes: Bytes) -> Bytes? {
        return (mockData[.combinedKeys] as? Bytes)
    }
    
    func sharedBlindedEncryptionKey(secretKey a: Bytes, otherBlindedPublicKey: Bytes, fromBlindedPublicKey kA: Bytes, toBlindedPublicKey kB: Bytes, genericHash: GenericHashType) -> Bytes? {
        return (mockData[.sharedBlindedEncryptionKey] as? Bytes)
    }
    
    func sessionId(_ sessionId: String, matchesBlindedId blindedSessionId: String, serverPublicKey: String) -> Bool {
        return ((mockData[.sessionIdMatches] as? Bool) ?? false)
    }
}
