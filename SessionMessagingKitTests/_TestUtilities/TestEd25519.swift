// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class TestEd25519: Ed25519Type, StaticMockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case verifySignature(signature: Data, publicKey: Data, data: Data) // TODO: Test the uniqueness of this
    }
    
    typealias Key = DataKey
    
    static var mockData: [DataKey: Any] = [:]
    
    // MARK: - SignType
    
    static func verifySignature(_ signature: Data, publicKey: Data, data: Data) throws -> Bool {
        return (mockData[.verifySignature(signature: signature, publicKey: publicKey, data: data)] as! Bool)
    }
}
