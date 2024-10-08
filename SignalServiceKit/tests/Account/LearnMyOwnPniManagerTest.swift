//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class LearnMyOwnPniManagerTest: XCTestCase {
    private var accountServiceClientMock: AccountServiceClientMock!
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var tsAccountManagerMock: MockTSAccountManager!

    private let db = InMemoryDB()
    private var scheduler: TestScheduler!

    private var learnMyOwnPniManager: LearnMyOwnPniManager!

    private var updatedPni: Pni?

    override func setUp() {
        accountServiceClientMock = .init()
        registrationStateChangeManagerMock = .init()
        tsAccountManagerMock = .init()

        registrationStateChangeManagerMock.didUpdateLocalPhoneNumberMock = { [weak self] phoneNumber, aci, pni in
            self?.tsAccountManagerMock.localIdentifiersMock = { .init(aci: aci, pni: pni, e164: phoneNumber) }
            self?.updatedPni = pni
        }

        scheduler = TestScheduler()
        let schedulers = TestSchedulers(scheduler: scheduler)
        schedulers.scheduler.start()

        learnMyOwnPniManager = LearnMyOwnPniManagerImpl(
            accountServiceClient: accountServiceClientMock,
            db: db,
            registrationStateChangeManager: registrationStateChangeManagerMock,
            schedulers: schedulers,
            tsAccountManager: tsAccountManagerMock
        )
    }

    override func tearDown() {
        accountServiceClientMock.whoAmIResult.ensureUnset()
    }

    func testSkipsIfLinkedDevice() async throws {
        tsAccountManagerMock.registrationStateMock = { .provisioned }

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()

        XCTAssertNil(self.updatedPni)
    }

    func testSkipsIfNoLocalIdentifiers() async throws {
        tsAccountManagerMock.localIdentifiersMock = { nil }
        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()

        XCTAssertNil(self.updatedPni)
    }

    func testFetchesPniIfMissingPni() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        accountServiceClientMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: localE164))

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()

        XCTAssertEqual(remotePni, self.updatedPni)
    }

    func testSkipsPniFetchIfPniPresent() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let localPni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: localPni, e164: localE164) }

        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()

        XCTAssertNil(self.updatedPni)
    }

    func testSkipsPniSaveIfMismatchedAci() async throws {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!

        let remoteAci = Aci.randomForTesting()
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        accountServiceClientMock.whoAmIResult = .value(.init(aci: remoteAci, pni: remotePni, e164: localE164))

        do {
            try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()
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
        accountServiceClientMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: remoteE164))

        do {
            try await learnMyOwnPniManager.learnMyOwnPniIfNecessary().awaitable()
            XCTFail("Expecting an error!")
        } catch {
            // We expect an error
        }

        XCTAssertNil(self.updatedPni)
    }

    func testConcurrentCalls() {
        let localAci = Aci.randomForTesting()
        let localE164 = E164("+17735550199")!
        let remotePni = Pni.randomForTesting()

        tsAccountManagerMock.localIdentifiersMock = { .init(aci: localAci, pni: nil, e164: localE164) }
        accountServiceClientMock.whoAmIResult = .value(.init(aci: localAci, pni: remotePni, e164: localE164))

        // Stop the scheduler and call twice; should only fetch once!
        scheduler.stop()
        let expectation1 = self.expectation(description: "1")
        learnMyOwnPniManager.learnMyOwnPniIfNecessary().observe(on: scheduler) {
            switch $0 {
            case .success:
                expectation1.fulfill()
            case .failure:
                XCTFail("Got error!")
            }
        }
        let expectation2 = self.expectation(description: "2")
        learnMyOwnPniManager.learnMyOwnPniIfNecessary().observe(on: scheduler) {
            switch $0 {
            case .success:
                expectation2.fulfill()
            case .failure:
                XCTFail("Got error!")
            }
        }
        scheduler.start()

        self.wait(for: [expectation1, expectation2], timeout: 1, enforceOrder: false)

        XCTAssertEqual(remotePni, self.updatedPni)
    }
}

private extension WhoAmIRequestFactory.Responses.WhoAmI {
    init(aci: Aci, pni: Pni, e164: E164) {
        self.init(aci: aci, pni: pni, e164: e164, usernameHash: nil)
    }
}

// MARK: - Mocks

// MARK: AccountServiceClient

private class AccountServiceClientMock: LearnMyOwnPniManagerImpl.Shims.AccountServiceClient {
    typealias WhoAmI = WhoAmIRequestFactory.Responses.WhoAmI

    var whoAmIResult: ConsumableMockPromise<WhoAmI> = .unset

    func getAccountWhoAmI() -> Promise<WhoAmI> {
        return whoAmIResult.consumeIntoPromise()
    }
}
