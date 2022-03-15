// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import YapDatabase

// FIXME: Turn this into a protocol to make mocking possible
final class TestTransaction: YapDatabaseReadWriteTransaction, Mockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case objectForKey
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    
    // MARK: - YapDatabaseReadWriteTransaction
    
    override func object(forKey key: String, inCollection collection: String?) -> Any? {
        return mockData[.objectForKey]
    }
    
    override func addCompletionQueue(_ completionQueue: DispatchQueue?, completionBlock: @escaping () -> Void) {
        completionBlock()
    }
}

extension TestTransaction: Mocked {
    static var mockValue: TestTransaction = TestTransaction()
}
