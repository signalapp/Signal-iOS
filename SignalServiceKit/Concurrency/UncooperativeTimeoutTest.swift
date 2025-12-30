//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct UncooperativeTimeoutTest {
    @Test
    func resolved() async throws {
        try await withUncooperativeTimeout(seconds: .day, operation: {})
    }

    @Test
    func timeout() async throws {
        var streamContinuation: AsyncStream<CheckedContinuation<Void, Never>>.Continuation! = nil
        let continuationStream = AsyncStream<CheckedContinuation<Void, Never>> { streamContinuation = $0 }
        await #expect(throws: UncooperativeTimeoutError.self) {
            try await withUncooperativeTimeout(seconds: 0) {
                // suspend forever until the timeout fires
                await withCheckedContinuation {
                    streamContinuation.yield($0)
                    streamContinuation.finish()
                }
            }
        }
        for await cleanupContinuation in continuationStream {
            cleanupContinuation.resume()
        }
    }
}
