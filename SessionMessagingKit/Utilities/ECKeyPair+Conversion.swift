// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Curve25519Kit
import SessionUtilitiesKit
import Sodium

public extension ECKeyPair {
    func convert(to targetPrefix: IdPrefix, with otherKey: String, using sodium: Sodium = Sodium()) throws -> ECKeyPair? {
        guard let publicKeyPrefix: IdPrefix = IdPrefix(with: hexEncodedPublicKey) else { return nil }
        
        switch (publicKeyPrefix, targetPrefix) {
            case (.standard, .blinded): // Only support standard -> blinded conversions
                // TODO: Figure out why this is broken...
//                guard let otherPubKeyData: Data = otherKey.data(using: .utf8) else { return nil }
                guard let otherPubKeyData: Data = otherKey.dataFromHex() else { return nil }
                guard let otherPubKeyHashBytes: Bytes = sodium.genericHash.hash(message: [UInt8](otherPubKeyData)) else {
                    return nil
                }
                guard let blindedPublicKey: Sodium.SharedSecret = sodium.sharedSecret(otherPubKeyHashBytes, [UInt8](publicKey)) else {
                    return nil
                }
                guard let blindedPrivateKey: Sodium.SharedSecret = sodium.sharedSecret(otherPubKeyHashBytes, [UInt8](privateKey)) else {
                    return nil
                }
                
                return try BlindedECKeyPair(publicKeyData: blindedPublicKey, privateKeyData: blindedPrivateKey)
                
            case (.standard, .standard): return self
            case (.blinded, .blinded): return self
            default: return nil
        }
    }
}
