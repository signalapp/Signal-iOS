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
    var isPrimaryDevice: Bool = true
    func isRegisteredAndReady(tx: SignalServiceKit.DBReadTransaction) -> Bool { isRegisteredAndReady }
    func isPrimaryDevice(tx: SignalServiceKit.DBReadTransaction) -> Bool { isPrimaryDevice }
}

class _PreKey_IdentityManagerMock: PreKey.Operation.Shims.IdentityManager {

    var aciKeyPair: ECKeyPair?
    var pniKeyPair: ECKeyPair?

    func identityKeyPair(for identity: OWSIdentity) -> ECKeyPair? {
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
    var currentPreKeyCount: Int = 0
    var currentPqPreKeyCount: Int = 0

    var identity: OWSIdentity?
    var identityKey: IdentityKey?
    var signedPreKeyRecord: SignedPreKeyRecord?
    var preKeyRecords: [PreKeyRecord]?
    var pqLastResortPreKeyRecord: KyberPreKeyRecord?
    var pqPreKeyRecords: [KyberPreKeyRecord]?
    var auth: ChatServiceAuth?

    override func getPreKeysCount(for identity: OWSIdentity) -> Promise<(ecCount: Int, pqCount: Int)> {
        return Promise.value((currentPreKeyCount, currentPqPreKeyCount))
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
        self.identity = identity
        self.identityKey = identityKey
        self.signedPreKeyRecord = signedPreKeyRecord
        self.preKeyRecords = preKeyRecords
        self.pqLastResortPreKeyRecord = pqLastResortPreKeyRecord
        self.pqPreKeyRecords = pqPreKeyRecords
        self.auth = auth
        return Promise.value(())
    }
}
