//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class LearnMyOwnPniManagerTest: XCTestCase {
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var tsAccountManagerMock: MockTSAccountManager!
    private var whoAmIManagerMock: MockWhoAmIManager!

    private let db = InMemoryDB()

    private var learnMyOwnPniManager: LearnMyOwnPniManager!

    private var updatedPni: Pni?

    override func setUp() {
        registrationStateChangeManagerMock = .init()
        tsAccountManagerMock = .init()
        whoAmIManagerMock = .init()

        registrationStateChangeManagerMock.didUpdateLocalPhoneNumberMock = { [weak self] phoneNumber, aci, pni in
            self?.tsAccountManagerMock.localIdentifiersMock = { .init(aci: aci, pni: pni, e164: phoneNumber) }
            self?.updatedPni = pni
        }

        learnMyOwnPniManager = LearnMyOwnPniManagerImpl(
            db: db,
            registrationStateChangeManager: registrationStateChangeManagerMock,
            tsAccountManager: tsAccountManagerMock,
            whoAmIManager: whoAmIManagerMock
        )
    }

    override func tearDown() {
        whoAmIManagerMock.whoAmIResult.ensureUnset()
    }

    func testSkipsIfLinkedDevice() async throws {
        tsAccountManagerMock.registrationStateMock = { .provisioned }

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary()

        XCTAssertNil(self.updatedPni)
    }

    func testSkipsIfNoLocalIdentifiers() async throws {
        tsAccountManagerMock.localIdentifiersMock = { nil }
        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary()

        XCTAssertNil(self.updatedPni)
    }

    func testFetchesPniIfMissingPni() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        whoAmIManagerMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: localE164))

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary()

        XCTAssertEqual(remotePni, self.updatedPni)
    }

    func testSkipsPniFetchIfPniPresent() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let localPni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: localPni, e164: localE164) }

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary()

        XCTAssertNil(self.updatedPni)
    }

    func testSkipsPniSaveIfMismatchedAci() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!

        let remoteAci = Aci.randomForTesting()
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        whoAmIManagerMock.whoAmIResult = .value(.init(aci: remoteAci, pni: remotePni, e164: localE164))

        do {
            try await learnMyOwnPniManager.learnMyOwnPniIfNecessary()
            XCTFail("Expecting an error!")
        } catch {
            // We expect an error
        }

        XCTAssertNil(self.updatedPni)
    }

    func testSkipsPniSaveIfMismatchedE164() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!

        let remotePni = Pni.randomForTesting()
        let remoteE164 = E164("+17735550198")!

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        whoAmIManagerMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: remoteE164))

        do {
            try await learnMyOwnPniManager.learnMyOwnPniIfNecessary()
            XCTFail("Expecting an error!")
        } catch {
            // We expect an error
        }

        XCTAssertNil(self.updatedPni)
    }

    func testConcurrentCalls() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        whoAmIManagerMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: localE164))

        let expectation1 = self.expectation(description: "1")
        let expectation2 = self.expectation(description: "2")

        // Call twice – expect only one fetch!
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            taskGroup.addTask {
                try await self.learnMyOwnPniManager.learnMyOwnPniIfNecessary()
                expectation1.fulfill()
            }

            taskGroup.addTask {
                try await self.learnMyOwnPniManager.learnMyOwnPniIfNecessary()
                expectation2.fulfill()
            }

            try await taskGroup.waitForAll()
        }

        await fulfillment(of: [expectation1, expectation2], timeout: 1, enforceOrder: false)

        XCTAssertEqual(remotePni, self.updatedPni)
    }
}

private extension WhoAmIManager.WhoAmIResponse {
    init(aci: Aci, pni: Pni, e164: E164) {
        self.init(
            aci: aci,
            pni: pni,
            e164: e164,
            usernameHash: nil,
            entitlements: Entitlements(backup: nil, badges: [])
        )
    }
}

// MARK: - Mocks

private class MockWhoAmIManager: WhoAmIManager {
    var whoAmIResult: ConsumableMockPromise<WhoAmIResponse> = .unset

    func makeWhoAmIRequest() async throws -> WhoAmIResponse {
        return try await whoAmIResult.consumeIntoPromise().awaitable()
    }
}
