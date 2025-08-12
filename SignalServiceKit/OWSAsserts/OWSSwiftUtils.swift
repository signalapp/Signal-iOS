//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
    line: Int = #line
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
    line: Int = #line
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
    line: Int = #line
) {
    logger.error(logMessage, file: file, function: function, line: line)
    if IsDebuggerAttached() {
        TrapDebugger()
    } else if Preferences.isFailDebugEnabled {
        Preferences.setIsFailDebugEnabled(false)
        logger.flush()
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
    line: Int = #line
) -> Never {
    logger.error(Thread.callStackSymbols.joined(separator: "\n"))
    owsFailDebug(logMessage, logger: logger, file: file, function: function, line: line)
    logger.flush()

    __crashDescriptively(logMessage)
}

/// Crash, injecting as much of the given log message as possible into the crash
/// report itself. Useful in cases where we can get an `.ips` file, but no logs.
public func __crashDescriptively(_ logMessageParam: String) -> Never {
    var logMessage = ScrubbingLogFormatter().redactMessage(logMessageParam)

    // Strip non-ASCII, to make the byte-range math below safe.
    logMessage = logMessage.filter { $0.isASCII }
    // Strip whitespace, to make the message as info-dense as possible.
    logMessage = logMessage.filter { !$0.isWhitespace }

    // Extract the first 63 bytes to use as the thread name, which is the max
    // accepted. More than this will result in the name being set to "".
    let threadNameSegment = String(logMessage.prefix(63))
    logMessage = String(logMessage.dropFirst(63))

    // Extract the next 127 bytes to use as the label for a DispatchQueue, which
    // is the max accepted. More than this will be truncated.
    let dispatchQueueNameSegment = String(logMessage.prefix(127))
    logMessage = String(logMessage.dropFirst(127))

    if let threadNameSegment = threadNameSegment.nilIfEmpty {
        Thread.current.name = threadNameSegment

        if let dispatchQueueNameSegment = dispatchQueueNameSegment.nilIfEmpty {
            DispatchQueue(label: dispatchQueueNameSegment).sync {
                fatalError(logMessageParam)
            }
        }
    }

    // Catch here in case we didn't have a long enough log message as to merit
    // crashing above in a dedicated DispatchQueue.
    fatalError(logMessageParam)
}

public func failIfThrows<T>(
    block: () throws -> T,
    file: String = #fileID,
    function: String = #function,
    line: Int = #line
) -> T {
    do {
        return try block()
    } catch {
        DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(userDefaults: CurrentAppContext().appUserDefaults(), error: error)
        owsFail("Couldn't write: \(error)", file: file, function: function, line: line)
    }
}

@inlinable
public func owsAssertDebug(
    _ condition: Bool,
    _ message: @autoclosure () -> String = String(),
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line
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
    line: Int = #line
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
        line: Int = #line
    ) -> Never {
        owsFail(logMessage, file: file, function: function, line: line)
    }
}
