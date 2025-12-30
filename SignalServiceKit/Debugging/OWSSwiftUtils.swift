//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/**
 * We synchronize access to state in this class using this queue.
 */
public func assertOnQueue(_ queue: DispatchQueue) {
    dispatchPrecondition(condition: .onQueue(queue))
}

@inlinable
public func AssertIsOnMainThread(
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    if !Thread.isMainThread {
        owsFailDebug("Must be on main thread.", logger: logger, file: file, function: function, line: line)
    }
}

@inlinable
public func AssertNotOnMainThread(
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    if Thread.isMainThread {
        owsFailDebug("Must be off main thread.", logger: logger, file: file, function: function, line: line)
    }
}

@inlinable
public func owsFailDebug(
    _ logMessage: String,
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    logger.error(logMessage, file: file, function: function, line: line)
    logger.flush()
    if IsDebuggerAttached() {
        TrapDebugger()
    } else if Preferences.isFailDebugEnabled {
        Preferences.setIsFailDebugEnabled(false)
        fatalError(logMessage)
    } else {
        assertionFailure(logMessage)
    }
}

@inlinable
public func owsFail(
    _ logMessage: String,
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) -> Never {
    logger.error(Thread.callStackSymbols.joined(separator: "\n"))
    owsFailDebug(logMessage, logger: logger, file: file, function: function, line: line)
    fatalError(logMessage)
}

public func failIfThrowsDatabaseError<T>(
    block: () throws(GRDB.DatabaseError) -> T,
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) -> T {
    failIfThrows(block: block, file: file, function: function, line: line)
}

@discardableResult
public func failIfThrows<T>(
    block: () throws -> T,
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) -> T {
    do {
        return try block()
    } catch {
        if let error = error as? DatabaseError, error.resultCode == .SQLITE_CORRUPT {
            DatabaseCorruptionState.flagDatabaseAsCorrupted(userDefaults: CurrentAppContext().appUserDefaults())
            owsFail("Failing due to database corruption. Extended result code: \(error.extendedResultCode)", file: file, function: function, line: line)
        } else {
            owsFail("Failing for unexpected throw: \(error.grdbErrorForLogging)", file: file, function: function, line: line)
        }
    }
}

@inlinable
public func owsAssertDebug(
    _ condition: Bool,
    _ message: @autoclosure () -> String = String(),
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    if !condition {
        let message: String = message()
        owsFailDebug(message.isEmpty ? "Assertion failed." : message, logger: logger, file: file, function: function, line: line)
    }
}

/// Like `Swift.precondition(_:)`, this will trap if `condition` evaluates to
/// `false`. Also performs additional logging before terminating the process.
/// See `owsFail(_:)` for more information about logging.
@inlinable
public func owsPrecondition(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = String(),
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    if !condition() {
        let message: String = message()
        owsFail(message.isEmpty ? "Assertion failed." : message, logger: logger, file: file, function: function, line: line)
    }
}

// MARK: -

@objc
public class OWSSwiftUtils: NSObject {
    // This method can be invoked from Obj-C to exit the app.
    @objc
    public class func owsFailObjC(
        _ logMessage: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) -> Never {
        owsFail(logMessage, file: file, function: function, line: line)
    }
}
