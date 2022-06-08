// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionMessagingKit

// FIXME: Turn this into a protocol to make mocking possible
class TestIncomingMessage: TSIncomingMessage, Mockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    var didCallSave: Bool = false
    var didCallRemove: Bool = false
    
    // MARK: - TSInteraction
    
    override func save(with transaction: YapDatabaseReadWriteTransaction) { didCallSave = true }
    override func remove(with transaction: YapDatabaseReadWriteTransaction) { didCallRemove = true }
}
