//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Waits until `isSatisfied()` returns true. Checks the initial result and
/// then re-checks the result each time notificationName fires.
struct NotificationPrecondition: Precondition {
    private let notificationName: Notification.Name
    private let isSatisfied: () -> Bool

    init(notificationName: Notification.Name, isSatisfied: @escaping () -> Bool) {
        self.notificationName = notificationName
        self.isSatisfied = isSatisfied
    }

    func waitUntilSatisfied() async -> WaitResult {
        let result = CancellableContinuation<Void>()
        let observer = NotificationCenter.default.addObserver(forName: notificationName, object: nil, queue: nil, using: { _ in
            if self.isSatisfied() {
                return result.resume(with: .success(()))
            }
        })
        defer {
            NotificationCenter.default.removeObserver(observer)
        }
        if isSatisfied() {
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
