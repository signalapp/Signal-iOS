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
        typealias DateProvider = _PreKey_DateProviderMock
        typealias IdentityManager = _PreKey_IdentityManagerMock
        typealias LinkedDevicePniKeyManager = _PreKey_LinkedDevicePniKeyManagerMock
        typealias MessageProcessor = _PreKey_MessageProcessorMock
        typealias SignalServiceClient = _PreKey_SignalServiceClientMock
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

class _PreKey_SignalServiceClientMock: SignalServiceClient {
    var currentPreKeyCount: Int?
    var currentPqPreKeyCount: Int?

    var setPreKeysResult: ConsumableMockPromise<Void> = .unset
    var identity: OWSIdentity?
    var signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord?
    var preKeyRecords: [SignalServiceKit.PreKeyRecord]?
    var pqLastResortPreKeyRecord: SignalServiceKit.KyberPreKeyRecord?
    var pqPreKeyRecords: [SignalServiceKit.KyberPreKeyRecord]?
    var auth: ChatServiceAuth?

    func getAvailablePreKeys(for identity: OWSIdentity) -> Promise<(ecCount: Int, pqCount: Int)> {
        return Promise.value((currentPreKeyCount!, currentPqPreKeyCount!))
    }

    func registerPreKeys(
        for identity: OWSIdentity,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord?,
        preKeyRecords: [SignalServiceKit.PreKeyRecord]?,
        pqLastResortPreKeyRecord: SignalServiceKit.KyberPreKeyRecord?,
        pqPreKeyRecords: [SignalServiceKit.KyberPreKeyRecord]?,
        auth: ChatServiceAuth
    ) -> Promise<Void> {
        return setPreKeysResult.consumeIntoPromise().map(on: SyncScheduler()) {
            self.identity = identity
            self.signedPreKeyRecord = signedPreKeyRecord
            self.preKeyRecords = preKeyRecords
            self.pqLastResortPreKeyRecord = pqLastResortPreKeyRecord
            self.pqPreKeyRecords = pqPreKeyRecords
            self.auth = auth
        }
    }

    func setCurrentSignedPreKey(_ signedPreKey: SignalServiceKit.SignedPreKeyRecord, for identity: OWSIdentity) -> Promise<Void> {
        owsFail("Not implemented!")
    }
    func requestUDSenderCertificate(uuidOnly: Bool) -> Promise<Data> {
        owsFail("Not implemented!")
    }
    func requestStorageAuth(chatServiceAuth: ChatServiceAuth) -> Promise<(username: String, password: String)> {
        owsFail("Not implemented!")
    }
    func getRemoteConfig(auth: ChatServiceAuth) -> Promise<RemoteConfigResponse> {
        owsFail("Not implemented!")
    }
    func updatePrimaryDeviceAccountAttributes(authedAccount: SignalServiceKit.AuthedAccount) async throws -> SignalServiceKit.AccountAttributes {
        owsFail("Not implemented!")
    }
    func updateSecondaryDeviceCapabilities(_ capabilities: SignalServiceKit.AccountAttributes.Capabilities, authedAccount: SignalServiceKit.AuthedAccount) async throws {
        owsFail("Not implemented!")
    }
}
