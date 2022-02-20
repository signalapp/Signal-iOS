// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class TestGenericHash: GenericHashType, Mockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case hash
        case hashOutputLength
        case hashSaltPersonal
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    
    // MARK: - SignType
    
    func hash(message: Bytes, key: Bytes?) -> Bytes? {
        return (mockData[.hash] as? Bytes)
    }
    
    func hash(message: Bytes, outputLength: Int) -> Bytes? {
        return (mockData[.hashOutputLength] as? Bytes)
    }
    
    func hashSaltPersonal(message: Bytes, outputLength: Int, key: Bytes?, salt: Bytes, personal: Bytes) -> Bytes? {
        return (mockData[.hashSaltPersonal] as? Bytes)
    }
}
