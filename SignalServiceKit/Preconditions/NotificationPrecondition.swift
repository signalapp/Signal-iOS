//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Waits until `isSatisfied()` returns true. Checks the initial result and
/// then re-checks the result each time notificationName fires.
public struct NotificationPrecondition: Precondition, Sendable {
    private let notificationNames: [Notification.Name]
    private let isSatisfied: @Sendable () async -> Bool

    public init(notificationName: Notification.Name, isSatisfied: @escaping @Sendable () async -> Bool) {
        self.init(notificationNames: [notificationName], isSatisfied: isSatisfied)
    }

    public init(notificationNames: [Notification.Name], isSatisfied: @escaping @Sendable () async -> Bool) {
        self.notificationNames = notificationNames
        self.isSatisfied = isSatisfied
    }

    public func waitUntilSatisfied() async -> WaitResult {
        let result = CancellableContinuation<Void>()
        let observers = self.notificationNames.map {
            return NotificationCenter.default.addObserver(forName: $0, object: nil, queue: nil, using: { _ in
                Task {
                    if await self.isSatisfied() {
                        result.resume(with: .success(()))
                    }
                }
            })
        }
        defer {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        if await isSatisfied() {
            return .satisfiedImmediately
        }
        do {
            try await result.wait()
            return .wasNotSatisfiedButIsNow
        } catch {
            return .canceled
        }
    }
}
