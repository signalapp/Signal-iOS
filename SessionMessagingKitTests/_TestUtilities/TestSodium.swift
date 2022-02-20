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
        case blindedKeyPair
        case sogsSignature
        case sharedEdSecret
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    
    // MARK: - SodiumType
    
    func getGenericHash() -> GenericHashType { return (mockData[.genericHash] as! GenericHashType) }
    
    func getAeadXChaCha20Poly1305Ietf() -> AeadXChaCha20Poly1305IetfType {
        return (mockData[.aeadXChaCha20Poly1305Ietf] as! AeadXChaCha20Poly1305IetfType)
    }
    
    func getSign() -> SignType { return (mockData[.sign] as! SignType) }
    
    func blindedKeyPair(serverPublicKey: String, edKeyPair: Box.KeyPair, genericHash: GenericHashType) -> Box.KeyPair? {
        return (mockData[.blindedKeyPair] as? Box.KeyPair)
    }
    
    func sogsSignature(message: Bytes, secretKey: Bytes, blindedSecretKey ka: Bytes, blindedPublicKey kA: Bytes) -> Bytes? {
        return (mockData[.sogsSignature] as? Bytes)
    }
    
    func sharedEdSecret(_ firstKeyBytes: [UInt8], _ secondKeyBytes: [UInt8]) -> Bytes? {
        return (mockData[.sharedEdSecret] as? Bytes)
    }
}
