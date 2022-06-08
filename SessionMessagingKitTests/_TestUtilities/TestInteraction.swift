// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionMessagingKit

// FIXME: Turn this into a protocol to make mocking possible
class TestInteraction: TSInteraction, Mockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case uniqueId
        case timestamp
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    var didCallSave: Bool = false
    
    // MARK: - TSInteraction
    
    override var uniqueId: String? {
        get { (mockData[.uniqueId] as? String) }
        set { mockData[.uniqueId] = newValue }
    }
    
    override var timestamp: UInt64 {
        (mockData[.timestamp] as! UInt64)
    }
    
    override func save(with transaction: YapDatabaseReadWriteTransaction) { didCallSave = true }
}
