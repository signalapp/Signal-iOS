//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct MonotonicDateTest {
    @Test
    func testMonotonicDate() {
        let a = MonotonicDate()
        let b = MonotonicDate()
        #expect(b - a >= MonotonicDuration(nanoseconds: 0))
        #expect(b >= a)
    }

    @Test
    func testMonotonicDateDifferent() {
        let a = MonotonicDate()
        var b = MonotonicDate()
        while a == b {
            b = MonotonicDate()
        }
        #expect(b - a > MonotonicDuration(nanoseconds: 0))
        #expect(b > a)
    }

    @Test
    func testAdding() {
        let a = MonotonicDate()
        let b = a.adding(1)
        #expect((b - a).nanoseconds == 1_000_000_000)
    }
}

struct MonotonicDurationTest {
    @Test
    func testMilliseconds() {
        #expect(MonotonicDuration(nanoseconds: 123_456).milliseconds == 0)
        #expect(MonotonicDuration(nanoseconds: 123_456_789).milliseconds == 123)
        #expect(MonotonicDuration(milliseconds: 123).nanoseconds == 123_000_000)
    }

    @Test
    func testSeconds() {
        #expect(MonotonicDuration(nanoseconds: 500_000_000).seconds == 0.5)
        #expect(MonotonicDuration(clampingSeconds: 0.5).nanoseconds == 500_000_000)

        #expect(MonotonicDuration(nanoseconds: 1_500_000_000).seconds == 1.5)
        #expect(MonotonicDuration(clampingSeconds: 1.5).nanoseconds == 1_500_000_000)
    }

    @Test
    func testDescription() {
        #expect(MonotonicDuration(nanoseconds: 123_456).debugDescription == "123456ns")
        #expect(MonotonicDuration(nanoseconds: 123_456_789).debugDescription == "123ms")
    }
}
