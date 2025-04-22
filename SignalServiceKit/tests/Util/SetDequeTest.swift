//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct SetDequeTest {
    @Test
    func testBasic() {
        var setDeque = SetDeque<String>()
        #expect(setDeque.popFront() == nil)
        #expect(setDeque.popFront() == nil)
        setDeque.pushBack("A")
        #expect(setDeque.contains("A"))
        #expect(setDeque.popFront() == "A")
        #expect(!setDeque.contains("A"))
        #expect(setDeque.popFront() == nil)
        setDeque.pushBack("B")
        setDeque.pushBack("C")
        setDeque.pushBack("C")
        #expect(setDeque.contains("B"))
        #expect(setDeque.contains("C"))
        #expect(setDeque.popFront() == "B")
        #expect(!setDeque.contains("B"))
        #expect(setDeque.popFront() == "C")
        #expect(!setDeque.contains("C"))
        #expect(setDeque.popFront() == nil)
    }

    @Test
    func testExpand() {
        var setDeque = SetDeque<String>()
        setDeque.pushBack("A")
        setDeque.pushBack("B")
        #expect(setDeque.popFront() == "A")
        for letter in "CDEFGHIJK" {
            setDeque.pushBack(String(letter))
        }
        #expect(setDeque.count == 10)
        for letter in "BCDEFGHIJK" {
            #expect(setDeque.contains(String(letter)))
            #expect(setDeque.popFront() == String(letter))
            #expect(!setDeque.contains(String(letter)))
        }
        #expect(setDeque.count == 0)
        #expect(setDeque.popFront() == nil)
    }
}
