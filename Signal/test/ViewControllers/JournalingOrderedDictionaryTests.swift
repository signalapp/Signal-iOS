//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import Signal

private enum StringChange: CustomDebugStringConvertible, Equatable {
    var debugDescription: String {
        switch self {
        case .replace(let value): return "replace(\(value))"
        }
    }
    case replace(String)
}

enum Letter: Hashable {
    case a
    case b
}

class JournalingOrderedDictionaryTest: XCTestCase {
    func testPrepend() {
        var sut = JournalingOrderedDictionary<Letter, String, StringChange>()
        sut.prepend(key: .a, value: "a")
        sut.prepend(key: .b, value: "b")
        XCTAssertEqual(sut.orderedKeys, [.b, .a])
        XCTAssertEqual(sut[.b], "b")
        XCTAssertEqual(sut[.a], "a")
        XCTAssertEqual(sut[0].value, "b")
        XCTAssertEqual(sut[1].value, "a")
        XCTAssertEqual(sut.journal, [
            .prepend,
            .prepend])

    }

    func testAppend() {
        var sut = JournalingOrderedDictionary<Letter, String, StringChange>()
        sut.append(key: .a, value: "a")
        sut.append(key: .b, value: "b")
        XCTAssertEqual(sut.orderedKeys, [.a, .b])
        XCTAssertEqual(sut[.a], "a")
        XCTAssertEqual(sut[.b], "b")
        XCTAssertEqual(sut[0].value, "a")
        XCTAssertEqual(sut[1].value, "b")
        XCTAssertEqual(sut.journal, [
            .append,
            .append])
    }

    func testReplace() {
        var sut = JournalingOrderedDictionary<Letter, String, StringChange>()
        sut.append(key: .a, value: "a")
        sut.append(key: .b, value: "b")

        sut.replaceValue(at: sut.orderedKeys.firstIndex(of: .a)!,
                         value: "A",
                         changes: [.replace("A")])
        XCTAssertEqual(sut.orderedKeys, [.a, .b])
        XCTAssertEqual(sut[.a], "A")
        XCTAssertEqual(sut[.b], "b")
        XCTAssertEqual(sut[0].value, "A")
        XCTAssertEqual(sut[1].value, "b")
        XCTAssertEqual(sut.journal, [
            .append,
            .append,
            .modify(index: 0, changes: [.replace("A")])])
    }

    func testRemove() {
        var sut = JournalingOrderedDictionary<Letter, String, StringChange>()
        sut.append(key: .a, value: "a")
        sut.append(key: .b, value: "b")
        sut.remove(at: 0)
        XCTAssertEqual(sut.orderedKeys, [.b])
        XCTAssertEqual(sut[.b], "b")
        XCTAssertEqual(sut[0].value, "b")
        XCTAssertEqual(sut.journal, [
            .append,
            .append,
            .remove(index: 0)])
    }

    func testRemoveAll() {
        var sut = JournalingOrderedDictionary<Letter, String, StringChange>()
        sut.append(key: .a, value: "a")
        sut.append(key: .b, value: "b")
        sut.removeAll()
        XCTAssertEqual(sut.orderedKeys, [])
        XCTAssertEqual(sut.journal, [.removeAll])
    }

    func testTakeJournal() {
        var sut = JournalingOrderedDictionary<Letter, String, StringChange>()
        sut.append(key: .a, value: "a")
        sut.append(key: .b, value: "b")
        let journal = sut.takeJournal()
        XCTAssertEqual(journal, [.append, .append])
        XCTAssertEqual(sut.orderedKeys, [.a, .b])
        XCTAssertEqual(sut[.a], "a")
        XCTAssertEqual(sut[.b], "b")
        XCTAssertEqual(sut[0].value, "a")
        XCTAssertEqual(sut[1].value, "b")
        XCTAssertEqual(sut.journal, [])
    }
}
