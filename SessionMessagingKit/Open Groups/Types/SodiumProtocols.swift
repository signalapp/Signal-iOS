// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium

public protocol SodiumType {
    func getGenericHash() -> GenericHashType
    
    func sharedSecret(_ firstKeyBytes: [UInt8], _ secondKeyBytes: [UInt8]) -> Sodium.SharedSecret?
}

public protocol GenericHashType {
    func hashSaltPersonal(message: Bytes, outputLength: Int, key: Bytes?, salt: Bytes, personal: Bytes) -> Bytes?
}

extension GenericHashType {
    func hashSaltPersonal(message: Bytes, outputLength: Int, salt: Bytes, personal: Bytes) -> Bytes? {
        return hashSaltPersonal(message: message, outputLength: outputLength, key: nil, salt: salt, personal: personal)
    }
}

extension Sodium: SodiumType {
    public func getGenericHash() -> GenericHashType { return genericHash }
}

extension GenericHash: GenericHashType {}

