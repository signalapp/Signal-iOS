//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class AuthorMergeHelperTest: XCTestCase {
    func testShouldCleanUp() throws {
        let phoneNumber = "+16505550101"
        let authorMergeHelper = AuthorMergeHelper(keyValueStoreFactory: InMemoryKeyValueStoreFactory())
        try MockDB().write { tx in
            XCTAssertTrue(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber, tx: tx))
            try authorMergeHelper.setCurrentVersion(nextVersion: 1, tx: tx)
            XCTAssertFalse(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber, tx: tx))
        }
    }

    func testShouldCleanUpThenJustLearnedThenRebuilt() throws {
        let phoneNumber = "+16505550101"
        let authorMergeHelper = AuthorMergeHelper(keyValueStoreFactory: InMemoryKeyValueStoreFactory())
        try MockDB().write { tx in
            authorMergeHelper.foundMissingAci(for: phoneNumber, tx: tx)
            try authorMergeHelper.setCurrentVersion(nextVersion: 1, tx: tx)
            XCTAssertTrue(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber, tx: tx))
            authorMergeHelper.maybeJustLearnedAci(for: phoneNumber, tx: tx)
            XCTAssertTrue(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber, tx: tx))
            try authorMergeHelper.setCurrentVersion(nextVersion: 2, tx: tx)
            XCTAssertFalse(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber, tx: tx))
        }
    }

    func testShouldCleanUpThenJustLearnedThenDisassociate() throws {
        let phoneNumber = "+16505550101"
        let authorMergeHelper = AuthorMergeHelper(keyValueStoreFactory: InMemoryKeyValueStoreFactory())
        try MockDB().write { tx in
            authorMergeHelper.foundMissingAci(for: phoneNumber, tx: tx)
            try authorMergeHelper.setCurrentVersion(nextVersion: 1, tx: tx)
            XCTAssertTrue(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber, tx: tx))
            authorMergeHelper.maybeJustLearnedAci(for: phoneNumber, tx: tx)
            XCTAssertTrue(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber, tx: tx))
            authorMergeHelper.didCleanUp(phoneNumber: phoneNumber, tx: tx)
            XCTAssertFalse(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber, tx: tx))
            try authorMergeHelper.setCurrentVersion(nextVersion: 2, tx: tx)
            XCTAssertFalse(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber, tx: tx))
        }
    }

    func testJustLearnedWhenNotJustLearned() throws {
        let phoneNumber = "+16505550101"
        let authorMergeHelper = AuthorMergeHelper(keyValueStoreFactory: InMemoryKeyValueStoreFactory())
        try MockDB().write { tx in
            authorMergeHelper.maybeJustLearnedAci(for: phoneNumber, tx: tx)
            XCTAssertEqual(authorMergeHelper.nextVersion(tx: tx), 1)
            try authorMergeHelper.setCurrentVersion(nextVersion: 1, tx: tx)
            authorMergeHelper.maybeJustLearnedAci(for: phoneNumber, tx: tx)
            XCTAssertEqual(authorMergeHelper.nextVersion(tx: tx), 1)
        }
    }

    func testInvalidatedWhileBuilding() throws {
        let phoneNumber1 = "+16505550101"
        let phoneNumber2 = "+16505550102"
        let phoneNumber3 = "+16505550103"
        let authorMergeHelper = AuthorMergeHelper(keyValueStoreFactory: InMemoryKeyValueStoreFactory())
        try MockDB().write { tx in
            authorMergeHelper.foundMissingAci(for: phoneNumber1, tx: tx)
            authorMergeHelper.foundMissingAci(for: phoneNumber2, tx: tx)
            authorMergeHelper.foundMissingAci(for: phoneNumber3, tx: tx)
            try authorMergeHelper.setCurrentVersion(nextVersion: 1, tx: tx)
            authorMergeHelper.maybeJustLearnedAci(for: phoneNumber1, tx: tx)
            XCTAssertEqual(authorMergeHelper.nextVersion(tx: tx), 2)
            authorMergeHelper.maybeJustLearnedAci(for: phoneNumber2, tx: tx)
            XCTAssertThrowsError(try authorMergeHelper.setCurrentVersion(nextVersion: 2, tx: tx))
            XCTAssertTrue(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber1, tx: tx))
            XCTAssertTrue(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber2, tx: tx))
            XCTAssertTrue(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber3, tx: tx))
            try authorMergeHelper.setCurrentVersion(nextVersion: 3, tx: tx)
            XCTAssertFalse(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber1, tx: tx))
            XCTAssertFalse(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber2, tx: tx))
            XCTAssertTrue(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber3, tx: tx))
        }
    }
}
