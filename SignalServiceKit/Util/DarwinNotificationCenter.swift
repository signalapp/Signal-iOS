//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import notify

/// Wrapper around notify to provide more ergonomic support to swift for cross-process notification
/// handling.
///
/// > Note: The original ObjC implementation of this code did not check the status result codes
/// > from the `notify_*` functions so we have kept that same behavior here. It may be advisable
/// > to change these to throwing at some point in the future and throw an error if the result code
/// > is not `NOTIFY_STATUS_OK`.
public enum DarwinNotificationCenter {

    public typealias ObserverToken = Int32
    public static let invalidObserverToken: ObserverToken = NOTIFY_TOKEN_INVALID

    /// Determines if an observer token is valid for a current registration.
    /// Negative integers are never valid. A positive or zero value is valid
    /// if the current process has a registration associated with the given value.
    ///
    /// - Parameter observer: The token returned by ``addObserver(name:queue:block:)``
    /// - Returns: `true` iff the given `observer` is valid
    public static func isValid(_ observer: ObserverToken) -> Bool {
        return notify_is_valid_token(observer)
    }

    /// Post a darwin notification that can be listened for from other processes.
    ///
    /// - Parameter name: The name of the notification to post.
    public static func postNotification(name: DarwinNotificationName) {
        _ = notify_post(name.rawValue)
    }

    /// Add an observer for a darwin notification of the given name.
    ///
    /// - Parameter name: The name of the notification to listen for.
    /// - Parameter queue: The queue to call back on.
    /// - Parameter block: The block to call back. Includes the observer token as an input parameter to allow
    /// removing the observer after receipt.
    /// - Returns: An ``ObserverToken`` that can be used to remove this observer.
    public static func addObserver(name: DarwinNotificationName, queue: DispatchQueue, block: @escaping (ObserverToken) -> Void) -> ObserverToken {
        var observer = Self.invalidObserverToken
        _ = notify_register_dispatch(name.rawValue, &observer, queue, block)
        return observer
    }

    /// Stops listening for notifications registered by the given observer token.
    ///
    /// - Parameter observer: The token returned by ``addObserver(name:queue:block:)`` for the notification you want to stop listening
    /// for.
    public static func removeObserver(_ observer: ObserverToken) {
        guard isValid(observer) else {
            owsFailDebug("Invalid observer token.")
            return
        }
        _ = notify_cancel(observer)
    }

    /// Retrieves the state for a given observer. This value can be set and read from
    /// any process listening for this notification. Note: ``setState(_:observer:)`` and ``getState(observer:)``
    /// are vulnerable to races.
    ///
    /// - Parameter observer: The token returned by ``addObserver(name:queue:block:)`` for the notification you want to get state for.
    /// - Returns: The state fetched from the observer.
    public static func getState(observer: ObserverToken) -> UInt64 {
        guard isValid(observer) else {
            owsFailDebug("Invalid observer token.")
            return 0
        }

        var result: UInt64 = 0
        _ = notify_get_state(observer, &result)
        return result
    }
}
