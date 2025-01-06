//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@testable import SignalServiceKit

//
//
// MARK: - Mocks
//
//
extension PreKey {
    enum Mocks {
        typealias APIClient = _PreKey_APIClientMock
        typealias DateProvider = _PreKey_DateProviderMock
        typealias IdentityManager = _PreKey_IdentityManagerMock
        typealias LinkedDevicePniKeyManager = _PreKey_LinkedDevicePniKeyManagerMock
        typealias MessageProcessor = _PreKey_MessageProcessorMock
    }
}

//
//
// MARK: - Mock Implementations
//
//

class _PreKey_IdentityManagerMock: PreKey.Shims.IdentityManager {

    var aciKeyPair: ECKeyPair?
    var pniKeyPair: ECKeyPair?

    func identityKeyPair(for identity: OWSIdentity, tx: SignalServiceKit.DBReadTransaction) -> ECKeyPair? {
        switch identity {
        case .aci:
            return aciKeyPair
        case .pni:
            return pniKeyPair
        }
    }

    func generateNewIdentityKeyPair() -> ECKeyPair { ECKeyPair.generateKeyPair() }

    func store(keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) {
        switch identity {
        case .aci:
            aciKeyPair = keyPair
        case .pni:
            pniKeyPair = keyPair
        }
    }
}

class _PreKey_LinkedDevicePniKeyManagerMock: LinkedDevicePniKeyManager {
    var hasSuspectedIssue: Bool = false

    func recordSuspectedIssueWithPniIdentityKey(tx: DBWriteTransaction) {
        hasSuspectedIssue = true
    }

    func validateLocalPniIdentityKeyIfNecessary(tx: DBReadTransaction) { owsFail("Not implemented!") }
}

struct _PreKey_MessageProcessorMock: PreKey.Shims.MessageProcessor {
    func waitForFetchingAndProcessing() -> Guarantee<Void> {
        return Guarantee<Void>.value(())
    }
}

class _PreKey_DateProviderMock {
    var currentDate: Date = Date()
    func targetDate() -> Date { return currentDate }
}

class _PreKey_APIClientMock: PreKeyTaskAPIClient {
    var currentPreKeyCount: Int?
    var currentPqPreKeyCount: Int?

    var setPreKeysResult: ConsumableMockPromise<Void> = .unset
    var identity: OWSIdentity?
    var signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord?
    var preKeyRecords: [SignalServiceKit.PreKeyRecord]?
    var pqLastResortPreKeyRecord: SignalServiceKit.KyberPreKeyRecord?
    var pqPreKeyRecords: [SignalServiceKit.KyberPreKeyRecord]?
    var auth: ChatServiceAuth?

    func getAvailablePreKeys(for identity: OWSIdentity) async throws -> (ecCount: Int, pqCount: Int) {
        return (currentPreKeyCount!, currentPqPreKeyCount!)
    }

    func registerPreKeys(
        for identity: OWSIdentity,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord?,
        preKeyRecords: [SignalServiceKit.PreKeyRecord]?,
        pqLastResortPreKeyRecord: SignalServiceKit.KyberPreKeyRecord?,
        pqPreKeyRecords: [SignalServiceKit.KyberPreKeyRecord]?,
        auth: ChatServiceAuth
    ) async throws {
        try await setPreKeysResult.consumeIntoPromise().awaitable()

        self.identity = identity
        self.signedPreKeyRecord = signedPreKeyRecord
        self.preKeyRecords = preKeyRecords
        self.pqLastResortPreKeyRecord = pqLastResortPreKeyRecord
        self.pqPreKeyRecords = pqPreKeyRecords
        self.auth = auth
    }
}
