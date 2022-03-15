// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionMessagingKit

// FIXME: Turn this into a protocol to make mocking possible
class TestGroupThread: TSGroupThread, Mockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case groupModel
        case interactions
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    var didCallSave: Bool = false
    
    // MARK: - TSGroupThread
    
    override var groupModel: TSGroupModel {
        get { (mockData[.groupModel] as! TSGroupModel) }
        set {}
    }
    
    override func enumerateInteractions(_ block: @escaping (TSInteraction) -> Void) {
        ((mockData[.interactions] as? [TSInteraction]) ?? []).forEach(block)
    }
    
    override func save(with transaction: YapDatabaseReadWriteTransaction) { didCallSave = true }
}
