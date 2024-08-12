//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

final class CooperativeTimeoutTest: XCTestCase {
    func testResolved() async throws {
        try await withCooperativeTimeout(
            seconds: kDayInterval,
            operation: {}
        )
    }

    func testTimeout() async throws {
        do {
            try await withCooperativeTimeout(
                seconds: 0,
                operation: { try await Task.sleep(nanoseconds: 1_000_000 * NSEC_PER_SEC) }
            )
            throw OWSGenericError("")
        } catch is CooperativeTimeoutError {
            // this is fine
        }
    }

    func testAlreadyCanceled() async throws {
        let cancellableTask = Task {
            while !Task.isCancelled { await Task.yield() }
            try await withCooperativeTimeout(
                seconds: kDayInterval,
                operation: { try await Task.sleep(nanoseconds: 1_000_000 * NSEC_PER_SEC) }
            )
        }
        cancellableTask.cancel()
        do {
            try await cancellableTask.value
            throw OWSGenericError("")
        } catch is CancellationError {
            // this is fine
        }
    }
}
