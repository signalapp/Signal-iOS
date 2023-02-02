//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class KBSAuthCredentialStorageTests: XCTestCase {

    typealias AuthCredential = KBSAuthCredentialStorageImpl.AuthCredential

    // NOTE: "passwords" here are written as if they were user-inputted
    // passwords in the conventional sense. In a real auth credential,
    // they are not that. It just makes the tests easier and more fun.

    func testConsolidation_noOverlap() {
        let consolidated = KBSAuthCredentialStorageImpl.consolidateCredentials(allUnsortedCredentials: [
            .init(username: "luke", password: "vaderismyfather", insertionTime: Date()),
            .init(username: "vader", password: "lukeismyson", insertionTime: Date().addingTimeInterval(-1))
        ])
        XCTAssertEqual(consolidated.map(\.username), ["luke", "vader"])
    }

    func testConsolidation_latestPerUsername() {
        let consolidated = KBSAuthCredentialStorageImpl.consolidateCredentials(allUnsortedCredentials: [
            .init(username: "luke", password: "leiaismysister?!?", insertionTime: Date()),
            .init(username: "luke", password: "vaderismyfather", insertionTime: Date().addingTimeInterval(-2)),
            .init(username: "vader", password: "lukeismyson", insertionTime: Date().addingTimeInterval(-1))
        ])
        XCTAssertEqual(consolidated.map(\.username), ["luke", "vader"])
        XCTAssertEqual(consolidated.map(\.password), ["leiaismysister?!?", "lukeismyson"])
    }

    func testConsolidation_sameCredentialDoesntUpdateDate() {
        let consolidated = KBSAuthCredentialStorageImpl.consolidateCredentials(allUnsortedCredentials: [
            .init(username: "luke", password: "vaderismyfather", insertionTime: Date()),
            .init(username: "luke", password: "vaderismyfather", insertionTime: Date().addingTimeInterval(-2)),
            .init(username: "vader", password: "lukeismyson", insertionTime: Date().addingTimeInterval(-1))
        ])
        XCTAssertEqual(consolidated.map(\.username), ["vader", "luke"])
        XCTAssertEqual(consolidated.map(\.password), ["lukeismyson", "vaderismyfather"])
    }

    func testConsolidation_greaterThanMaxCount() {
        let now = Date()
        var credentials = [AuthCredential]()
        var expectedConsolidatedCredentials = [AuthCredential]()
        for i in 0..<(KBS.maxKBSAuthCredentialsBackedUp * 2) {
            var credential = AuthCredential(
                username: "\(i)",
                password: "\(i)",
                insertionTime: now.addingTimeInterval(Double(-i))
            )
            credentials.append(credential)
            if i < KBS.maxKBSAuthCredentialsBackedUp {
                expectedConsolidatedCredentials.append(credential)
            }
            for j in 1...5 {
                // Add extra entries per each username, should only keep the latest one.
                credential = AuthCredential(
                    username: "\(i)",
                    password: "\(i)_\(j)",
                    insertionTime: now.addingTimeInterval(Double(-i - j))
                )
                credentials.append(credential)
            }
        }
        // We inserted them in order. To test sorting, scramble them.
        credentials = credentials.shuffled()
        let consolidated = KBSAuthCredentialStorageImpl.consolidateCredentials(allUnsortedCredentials: credentials)
        XCTAssertEqual(consolidated, expectedConsolidatedCredentials)
    }
}
