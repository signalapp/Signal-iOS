//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation

extension Notification.Name {
    /// Posted (on the main thread) when ``ClockSkewManager/isClockSkewed``
    /// changes.
    public static let clockSkewDidChange = Notification.Name("ClockSkewDidChange")

    /// Posted (on the main thread) when
    /// ``ClockSkewManager/shouldBlockConnections`` changes.
    public static let clockSkewShouldBlockConnectionsDidChange = Notification.Name("ClockSkewShouldBlockConnectionsDidChange")

    /// Posted (on the main thread) when the device's clock has changed, and so
    /// the last measured skew is no longer trustworthy.
    public static let clockSkewShouldBeRemeasured = Notification.Name("ClockSkewShouldBeRemeasured")
}

// MARK: -

/// Represents a failure due to the client's clock being too far skewed from the
/// server's.
public struct ClockSkewError: Error {}

// MARK: -

/// Tracks whether the device's clock is skewed too far from the server's clock.
///
/// When the auth chat connection opens, the server reports its current timestamp
/// (see `serverDidReportTimestamp`). If that timestamp differs from the device
/// clock by more than `maximumAllowedClockSkew`, we consider the clock "skewed".
public final class ClockSkewManager {

    /// The clock is considered skewed if it differs from the server's clock by
    /// more than this.
    static let maximumAllowedClockSkew: TimeInterval = .day

    private let dateProvider: DateProvider
    private let logger = PrefixedLogger(prefix: "[ClockSkew]")
    private let notificationCenter: NotificationCenter

    private struct State {
        /// The most recently observed skew between the device's clock and the
        /// server's (positive if the device is ahead), or `nil` if unknown.
        var lastReportedClockSkew: TimeInterval?
        /// Whether the chat connections should be blocked.
        var shouldBlockConnections: Bool = false
    }

    private let state = AtomicValue(State(), lock: .init())

    /// Whether the device's clock is known to be skewed too far from the server's.
    ///
    /// This value may change when the server reports a new timestamp.
    public var isClockSkewed: Bool {
        Self.isSkewed(state.get().lastReportedClockSkew)
    }

    /// Whether `ChatConnection`s should be blocked due to clock skew.
    public var shouldBlockConnections: Bool {
        state.get().shouldBlockConnections
    }

    public init(
        dateProvider: @escaping DateProvider,
        notificationCenter: NotificationCenter,
    ) {
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(systemClockDidChange),
            name: .NSSystemClockDidChange,
            object: nil,
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil,
        )
    }

    /// Records the server's current timestamp, in milliseconds since the Unix
    /// epoch, and re-evaluates clock skew.
    public func serverDidReportTimestamp(_ serverTimestampMs: UInt64) {
        let serverDate = Date(millisecondsSince1970: serverTimestampMs)
        let skew = dateProvider().timeIntervalSince(serverDate)
        logger.info("Server reported clock skew of \(skew)s")
        updateState {
            $0.lastReportedClockSkew = skew
            $0.shouldBlockConnections = Self.isSkewed(skew)
        }
    }

    @objc
    private func systemClockDidChange() {
        // Our last-measured skew was against the old clock, so we need to
        // re-measure.
        //
        // Post before unblocking, so that connections cycle while they're still
        // blocked. Unblocking first would let them open, only to be immediately
        // torn down by the cycle.
        postNotification(.clockSkewShouldBeRemeasured)
        unblockConnections()
    }

    @objc
    private func applicationDidBecomeActive() {
        // We don't need to force a re-measure. However, if we were blocking the
        // connection when we suspended we want to let it reconnect and
        // organically re-measure in case the clock changed while we were
        // suspended.
        unblockConnections()
    }

    private func unblockConnections() {
        updateState {
            $0.shouldBlockConnections = false
        }
    }

    private static func isSkewed(_ skew: TimeInterval?) -> Bool {
        guard let skew else {
            return false
        }
        return abs(skew) > maximumAllowedClockSkew
    }

    private func updateState(_ mutate: (inout State) -> Void) {
        let (isClockSkewedChanged, shouldBlockConnectionsChanged) = state.update { current in
            let old = current
            mutate(&current)
            return (
                Self.isSkewed(old.lastReportedClockSkew) != Self.isSkewed(current.lastReportedClockSkew),
                old.shouldBlockConnections != current.shouldBlockConnections,
            )
        }
        guard isClockSkewedChanged || shouldBlockConnectionsChanged else {
            return
        }
        logger.warn("Clock skew state changed; isClockSkewed: \(isClockSkewed), shouldBlockConnections: \(shouldBlockConnections)")
        if isClockSkewedChanged {
            postNotification(.clockSkewDidChange)
        }
        if shouldBlockConnectionsChanged {
            postNotification(.clockSkewShouldBlockConnectionsDidChange)
        }
    }

    private func postNotification(
        _ name: Notification.Name,
        function: String = #function,
        line: Int = #line,
    ) {
        logger.info("Posting \(name.rawValue)", function: function, line: line)
        notificationCenter.postOnMainThread(name: name, object: nil)
    }
}
