//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import PromiseKit

// A base class for SDSDatabaseStorage and SDSAnyDatabaseQueue.
@objc
public class SDSTransactable: NSObject {
    public func read(block: @escaping (SDSAnyReadTransaction) -> Void) {
        owsFail("Method should be implemented by subclasses.")
    }

    public func write(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        owsFail("Method should be implemented by subclasses.")
    }
}

// MARK: - Async Methods

@objc
public extension SDSTransactable {
    func asyncRead(block: @escaping (SDSAnyReadTransaction) -> Void) {
        asyncRead(block: block, completion: { })
    }

    func asyncRead(block: @escaping (SDSAnyReadTransaction) -> Void, completion: @escaping () -> Void) {
        asyncRead(block: block, completionQueue: .main, completion: completion)
    }

    func asyncRead(block: @escaping (SDSAnyReadTransaction) -> Void, completionQueue: DispatchQueue, completion: @escaping () -> Void) {
        DispatchQueue.global().async {
            self.read(block: block)

            completionQueue.async(execute: completion)
        }
    }

    func asyncWrite(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        asyncWrite(block: block, completion: { })
    }

    func asyncWrite(block: @escaping (SDSAnyWriteTransaction) -> Void, completion: @escaping () -> Void) {
        asyncWrite(block: block, completionQueue: .main, completion: completion)
    }

    func asyncWrite(block: @escaping (SDSAnyWriteTransaction) -> Void, completionQueue: DispatchQueue, completion: @escaping () -> Void) {
        DispatchQueue.global().async {
            self.write(block: block)

            completionQueue.async(execute: completion)
        }
    }
}

// MARK: - Promises

public extension SDSTransactable {
    @objc
    func readPromise(_ block: @escaping (SDSAnyReadTransaction) -> Void) -> AnyPromise {
        return AnyPromise(read(.promise, block) as Promise<Void>)
    }

    func read<T>(_: PMKNamespacer, _ block: @escaping (SDSAnyReadTransaction) -> T) -> Promise<T> {
        return Promise { resolver in
            DispatchQueue.global().async {
                resolver.fulfill(self.read(block: block))
            }
        }
    }

    @objc
    func writePromise(_ block: @escaping (SDSAnyWriteTransaction) -> Void) -> AnyPromise {
        return AnyPromise(write(.promise, block) as Promise<Void>)
    }

    func write<T>(_: PMKNamespacer, _ block: @escaping (SDSAnyWriteTransaction) -> T) -> Promise<T> {
        return Promise { resolver in
            DispatchQueue.global().async {
                resolver.fulfill(self.write(block: block))
            }
        }
    }
}

// MARK: - Value Methods

public extension SDSTransactable {
    @discardableResult
    func read<T>(block: @escaping (SDSAnyReadTransaction) -> T) -> T {
        var value: T!
        read { (transaction) in
            value = block(transaction)
        }
        return value
    }

    @discardableResult
    func read<T>(block: @escaping (SDSAnyReadTransaction) throws -> T) throws -> T {
        var value: T!
        var thrown: Error?
        read { (transaction) in
            do {
                value = try block(transaction)
            } catch {
                thrown = error
            }
        }

        if let error = thrown {
            throw error.grdbErrorForLogging
        }

        return value
    }

    @discardableResult
    func write<T>(block: @escaping (SDSAnyWriteTransaction) -> T) -> T {
        var value: T!
        write { (transaction) in
            value = block(transaction)
        }
        return value
    }

    @discardableResult
    func write<T>(block: @escaping (SDSAnyWriteTransaction) throws -> T) throws -> T {
        var value: T!
        var thrown: Error?
        write { (transaction) in
            do {
                value = try block(transaction)
            } catch {
                thrown = error
            }
        }
        if let error = thrown {
            throw error.grdbErrorForLogging
        }
        return value
    }
}
