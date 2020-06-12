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

    public func write(file: String = #file,
                      function: String = #function,
                      line: Int = #line,
                      block: @escaping (SDSAnyWriteTransaction) -> Void) {
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
}

// MARK: - Async Methods

// NOTE: This extension is not @objc. See SDSDatabaseStorage+Objc.h.
public extension SDSTransactable {
    func asyncWrite(file: String = #file,
                    function: String = #function,
                    line: Int = #line,
                    block: @escaping (SDSAnyWriteTransaction) -> Void) {
        asyncWrite(file: file,
                   function: function,
                   line: line,
                   block: block,
                   completion: { })
    }

    func asyncWrite(file: String = #file,
                    function: String = #function,
                    line: Int = #line,
                    block: @escaping (SDSAnyWriteTransaction) -> Void,
                    completion: @escaping () -> Void) {
        asyncWrite(file: file,
                   function: function,
                   line: line,
                   block: block,
                   completionQueue: .main,
                   completion: completion)
    }

    func asyncWrite(file: String = #file,
                    function: String = #function,
                    line: Int = #line,
                    block: @escaping (SDSAnyWriteTransaction) -> Void,
                    completionQueue: DispatchQueue,
                    completion: @escaping () -> Void) {
        DispatchQueue.global().async {
            self.write(file: file,
                       function: function,
                       line: line,
                       block: block)

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

    func read<T>(_: PMKNamespacer, _ block: @escaping (SDSAnyReadTransaction) throws -> T) -> Promise<T> {
        return Promise { resolver in
            DispatchQueue.global().async {
                do {
                    resolver.fulfill(try self.read(block: block))
                } catch {
                    resolver.reject(error)
                }
            }
        }
    }

    // NOTE: This method is not @objc. See SDSDatabaseStorage+Objc.h.
    func writePromise(_ block: @escaping (SDSAnyWriteTransaction) -> Void) -> AnyPromise {
        return AnyPromise(write(.promise, block) as Promise<Void>)
    }

    func write<T>(_: PMKNamespacer,
                  file: String = #file,
                  function: String = #function,
                  line: Int = #line,
                  _ block: @escaping (SDSAnyWriteTransaction) -> T) -> Promise<T> {
        return Promise { resolver in
            DispatchQueue.global().async {
                resolver.fulfill(self.write(file: file,
                                            function: function,
                                            line: line,
                                            block: block))
            }
        }
    }

    func write<T>(_: PMKNamespacer,
                  file: String = #file,
                  function: String = #function,
                  line: Int = #line,
                  _ block: @escaping (SDSAnyWriteTransaction) throws -> T) -> Promise<T> {
        return Promise { resolver in
            DispatchQueue.global().async {
                do {
                    resolver.fulfill(try self.write(file: file,
                                                    function: function,
                                                    line: line,
                                                    block: block))
                } catch {
                    resolver.reject(error)
                }
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
    func write<T>(file: String = #file,
                  function: String = #function,
                  line: Int = #line,
                  block: @escaping (SDSAnyWriteTransaction) -> T) -> T {
        var value: T!
        write(file: file,
              function: function,
              line: line) { (transaction) in
            value = block(transaction)
        }
        return value
    }

    @discardableResult
    func write<T>(file: String = #file,
                  function: String = #function,
                  line: Int = #line,
                  block: @escaping (SDSAnyWriteTransaction) throws -> T) throws -> T {
        var value: T!
        var thrown: Error?
        write(file: file,
              function: function,
              line: line) { (transaction) in
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

// MARK: - @objc macro methods

// NOTE: Do NOT call these methods directly. See SDSDatabaseStorage+Objc.h.
@objc
public extension SDSTransactable {
    @available(*, deprecated, message: "Use DatabaseStorageWrite() instead")
    func __private_objc_write(file: String = #file,
                               function: String = #function,
                               line: Int = #line,
                               block: @escaping (SDSAnyWriteTransaction) -> Void) {
        write(file: file, function: function, line: line, block: block)
    }

    @available(*, deprecated, message: "Use DatabaseStorageAsyncWrite() instead")
    func __private_objc_asyncWrite(file: String = #file,
                    function: String = #function,
                    line: Int = #line,
                    block: @escaping (SDSAnyWriteTransaction) -> Void) {
        asyncWrite(file: file,
                   function: function,
                   line: line,
                   block: block,
                   completion: { })
    }
}
