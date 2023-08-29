//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

//
//
// MARK: - Mocks
//
//
extension PreKey.Operation {
    enum Mocks {
        typealias AccountManager = _PreKey_AccountManagerMock
        typealias AccountServiceClient = _PreKey_AccountServiceClientMock
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

class _PreKey_AccountManagerMock: PreKey.Operation.Shims.AccountManager {
    var isRegisteredAndReady: Bool = true
    func isRegisteredAndReady(tx: SignalServiceKit.DBReadTransaction) -> Bool { isRegisteredAndReady }
}

class _PreKey_IdentityManagerMock: PreKey.Operation.Shims.IdentityManager {

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

    func generateNewIdentityKeyPair() -> ECKeyPair { Curve25519.generateKeyPair() }

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

struct _PreKey_MessageProcessorMock: PreKey.Operation.Shims.MessageProcessor {
    func fetchingAndProcessingCompletePromise() -> Promise<Void> {
        return Promise<Void>.value(())
    }
}

class _PreKey_DateProviderMock {
    var currentDate: Date = Date()
    func targetDate() -> Date { return currentDate }
}

class _PreKey_AccountServiceClientMock: FakeAccountServiceClient {
    var currentPreKeyCount: Int?
    var currentPqPreKeyCount: Int?

    var setPreKeysResult: ConsumableMockPromise<Void> = .unset
    var identity: OWSIdentity?
    var identityKey: IdentityKey?
    var signedPreKeyRecord: SignedPreKeyRecord?
    var preKeyRecords: [PreKeyRecord]?
    var pqLastResortPreKeyRecord: KyberPreKeyRecord?
    var pqPreKeyRecords: [KyberPreKeyRecord]?
    var auth: ChatServiceAuth?

    private let schedulers: Schedulers

    init(schedulers: Schedulers) {
        self.schedulers = schedulers
    }

    override func getPreKeysCount(for identity: OWSIdentity) -> Promise<(ecCount: Int, pqCount: Int)> {
        return Promise.value((currentPreKeyCount!, currentPqPreKeyCount!))
    }

    override func setPreKeys(
        for identity: OWSIdentity,
        identityKey: IdentityKey,
        signedPreKeyRecord: SignedPreKeyRecord?,
        preKeyRecords: [PreKeyRecord]?,
        pqLastResortPreKeyRecord: KyberPreKeyRecord?,
        pqPreKeyRecords: [KyberPreKeyRecord]?,
        auth: ChatServiceAuth
    ) -> Promise<Void> {
        return setPreKeysResult.consumeIntoPromise().map(on: schedulers.sync) {
            self.identity = identity
            self.identityKey = identityKey
            self.signedPreKeyRecord = signedPreKeyRecord
            self.preKeyRecords = preKeyRecords
            self.pqLastResortPreKeyRecord = pqLastResortPreKeyRecord
            self.pqPreKeyRecords = pqPreKeyRecords
            self.auth = auth
        }
    }
}
