//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

// A base class for SDSDatabaseStorage and SDSAnyDatabaseQueue.
@objc
public class SDSTransactable: NSObject {
    fileprivate let asyncWriteQueue = DispatchQueue(label: "org.signal.database.write-async")

    public func read(file: String = #file,
                     function: String = #function,
                     line: Int = #line,
                     block: (SDSAnyReadTransaction) -> Void) {
        owsFail("Method should be implemented by subclasses.")
    }

    public func write(file: String = #file,
                      function: String = #function,
                      line: Int = #line,
                      block: (SDSAnyWriteTransaction) -> Void) {
        owsFail("Method should be implemented by subclasses.")
    }
}

// MARK: - Async Methods

public extension SDSTransactable {
    @objc(asyncReadWithBlock:)
    func asyncReadObjC(block: @escaping (SDSAnyReadTransaction) -> Void) {
        asyncRead(file: "objc", function: "block", line: 0, block: block)
    }

    @objc(asyncReadWithBlock:completion:)
    func asyncReadObjC(block: @escaping (SDSAnyReadTransaction) -> Void, completion: @escaping () -> Void) {
        asyncRead(file: "objc", function: "block", line: 0, block: block, completion: completion)
    }

    func asyncRead(file: String = #file,
                   function: String = #function,
                   line: Int = #line,
                   block: @escaping (SDSAnyReadTransaction) -> Void,
                   completionQueue: DispatchQueue = .main,
                   completion: (() -> Void)? = nil) {
        DispatchQueue.global().async {
            self.read(file: file, function: function, line: line, block: block)

            if let completion = completion {
                completionQueue.async(execute: completion)
            }
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
                   completion: nil)
    }

    func asyncWrite(file: String = #file,
                    function: String = #function,
                    line: Int = #line,
                    block: @escaping (SDSAnyWriteTransaction) -> Void,
                    completion: (() -> Void)?) {
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
                    completion: (() -> Void)?) {
        self.asyncWriteQueue.async {
            self.write(file: file,
                       function: function,
                       line: line,
                       block: block)

            if let completion = completion {
                completionQueue.async(execute: completion)
            }
        }
    }
}

// MARK: - Promises

public extension SDSTransactable {
    @objc
    func readPromise(file: String = #file,
                     function: String = #function,
                     line: Int = #line,
                     _ block: @escaping (SDSAnyReadTransaction) -> Void) -> AnyPromise {
        return AnyPromise(read(.promise, file: file, function: function, line: line, block) as Promise<Void>)
    }

    func read<T>(_: PromiseNamespace,
                 file: String = #file,
                 function: String = #function,
                 line: Int = #line,
                 _ block: @escaping (SDSAnyReadTransaction) -> T) -> Promise<T> {
        return Promise { future in
            DispatchQueue.global().async {
                future.resolve(self.read(file: file, function: function, line: line, block: block))
            }
        }
    }

    func read<T>(_: PromiseNamespace,
                 file: String = #file,
                 function: String = #function,
                 line: Int = #line,
                 _ block: @escaping (SDSAnyReadTransaction) throws -> T) -> Promise<T> {
        return Promise { future in
            DispatchQueue.global().async {
                do {
                    future.resolve(try self.read(file: file, function: function, line: line, block: block))
                } catch {
                    future.reject(error)
                }
            }
        }
    }

    // NOTE: This method is not @objc. See SDSDatabaseStorage+Objc.h.
    func writePromise(_ block: @escaping (SDSAnyWriteTransaction) -> Void) -> AnyPromise {
        return AnyPromise(write(.promise, block) as Promise<Void>)
    }

    func write<T>(_: PromiseNamespace,
                  file: String = #file,
                  function: String = #function,
                  line: Int = #line,
                  _ block: @escaping (SDSAnyWriteTransaction) -> T) -> Promise<T> {
        return Promise { future in
            self.asyncWriteQueue.async {
                future.resolve(self.write(file: file,
                                            function: function,
                                            line: line,
                                            block: block))
            }
        }
    }

    func write<T>(_: PromiseNamespace,
                  file: String = #file,
                  function: String = #function,
                  line: Int = #line,
                  _ block: @escaping (SDSAnyWriteTransaction) throws -> T) -> Promise<T> {
        return Promise { future in
            self.asyncWriteQueue.async {
                do {
                    future.resolve(try self.write(file: file,
                                                    function: function,
                                                    line: line,
                                                    block: block))
                } catch {
                    future.reject(error)
                }
            }
        }
    }
}

// MARK: - Value Methods

public extension SDSTransactable {
    @discardableResult
    func read<T>(file: String = #file,
                 function: String = #function,
                 line: Int = #line,
                 block: (SDSAnyReadTransaction) -> T) -> T {
        var value: T!
        read(file: file, function: function, line: line) { (transaction) in
            value = block(transaction)
        }
        return value
    }

    @discardableResult
    func read<T>(file: String = #file,
                 function: String = #function,
                 line: Int = #line,
                 block: (SDSAnyReadTransaction) throws -> T) throws -> T {
        var value: T!
        var thrown: Error?
        read(file: file, function: function, line: line) { (transaction) in
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
                  block: (SDSAnyWriteTransaction) -> T) -> T {
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
                  block: (SDSAnyWriteTransaction) throws -> T) throws -> T {
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
    func __private_objc_write(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (SDSAnyWriteTransaction) -> Void
    ) {
        write(file: file, function: function, line: line, block: block)
    }

    @available(*, deprecated, message: "Use DatabaseStorageAsyncWrite() instead")
    func __private_objc_asyncWrite(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (SDSAnyWriteTransaction) -> Void
    ) {
        asyncWrite(file: file,
                   function: function,
                   line: line,
                   block: block,
                   completion: nil)
    }
}
