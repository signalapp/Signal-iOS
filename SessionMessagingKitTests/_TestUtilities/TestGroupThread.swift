// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionMessagingKit

// FIXME: Turn this into a protocol to make mocking possible
class TestGroupThread: TSGroupThread, Mockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case uniqueId
        case groupModel
        case interactions
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    var numSaveCalls: Int = 0
    var didCallRemoveAllThreadInteractions: Bool = false
    var didCallRemove: Bool = false
    
    // MARK: - TSGroupThread
    
    override var uniqueId: String? {
        get { (mockData[.uniqueId] as? String) }
        set {}
    }
    
    override var groupModel: TSGroupModel {
        get { (mockData[.groupModel] as! TSGroupModel) }
        set { mockData[.groupModel] = newValue }
    }
    
    override func enumerateInteractions(_ block: @escaping (TSInteraction) -> Void) {
        ((mockData[.interactions] as? [TSInteraction]) ?? []).forEach(block)
    }
    
    override func enumerateInteractions(with transaction: YapDatabaseReadTransaction, using block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop: ObjCBool = false
        for interaction in ((mockData[.interactions] as? [TSInteraction]) ?? []) {
            block(interaction, &stop)
            
            if stop.boolValue { break }
        }
    }
    
    override func removeAllThreadInteractions(with transaction: YapDatabaseReadWriteTransaction) {
        didCallRemoveAllThreadInteractions = true
    }
    
    override func remove(with transaction: YapDatabaseReadWriteTransaction) {
        didCallRemove = true
    }
    
    override func save(with transaction: YapDatabaseReadWriteTransaction) { numSaveCalls += 1 }
}
