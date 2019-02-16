//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension YapDatabaseConnection {

    @objc
    func readWritePromise(_ block: @escaping (YapDatabaseReadWriteTransaction) -> Void) -> AnyPromise {
        return AnyPromise(readWritePromise(block) as Promise<Void>)
    }

    func readWritePromise(_ block: @escaping (YapDatabaseReadWriteTransaction) -> Void) -> Promise<Void> {
        return Promise { resolver in
            self.asyncReadWrite(block, completionBlock: resolver.fulfill)
        }
    }
}
