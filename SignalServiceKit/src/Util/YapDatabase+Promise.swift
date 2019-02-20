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

    func read(_ block: @escaping (YapDatabaseReadTransaction) throws -> Void) throws {
        var errorToRaise: Error? = nil

        read { transaction in
            do {
                try block(transaction)
            } catch {
                errorToRaise = error
            }
        }

        if let errorToRaise = errorToRaise {
            throw errorToRaise
        }
    }

    func readWrite(_ block: @escaping (YapDatabaseReadWriteTransaction) throws -> Void) throws {
        var errorToRaise: Error? = nil

        readWrite { transaction in
            do {
                try block(transaction)
            } catch {
                errorToRaise = error
            }
        }

        if let errorToRaise = errorToRaise {
            throw errorToRaise
        }
    }
}
