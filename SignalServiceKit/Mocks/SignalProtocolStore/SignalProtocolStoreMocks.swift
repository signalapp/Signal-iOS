//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
import LibSignalClient

extension SignalProtocolStore {
    static func mock(identity: OWSIdentity, preKeyStore: PreKeyStore) -> Self {
        return SignalProtocolStore(
            sessionStore: MockSessionStore(),
            preKeyStore: PreKeyStoreImpl(for: identity, preKeyStore: preKeyStore),
            signedPreKeyStore: SignedPreKeyStoreImpl(for: identity, preKeyStore: preKeyStore),
            kyberPreKeyStore: KyberPreKeyStoreImpl(for: identity, dateProvider: Date.provider, preKeyStore: preKeyStore),
        )
    }
}

class MockSessionStore: SignalSessionStore {
    func mightContainSession(for recipient: SignalRecipient, tx: DBReadTransaction) -> Bool { false }
    func mergeRecipient(_ recipient: SignalRecipient, into targetRecipient: SignalRecipient, tx: DBWriteTransaction) { }
    func archiveAllSessions(for serviceId: ServiceId, tx: DBWriteTransaction) { }
    func archiveAllSessions(for address: SignalServiceAddress, tx: DBWriteTransaction) { }
    func archiveSession(for serviceId: ServiceId, deviceId: DeviceId, tx: DBWriteTransaction) { }
    func loadSession(for serviceId: ServiceId, deviceId: DeviceId, tx: DBReadTransaction) throws -> LibSignalClient.SessionRecord? { nil }
    func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> LibSignalClient.SessionRecord? { nil }
    func resetSessionStore(tx: DBWriteTransaction) { }
    func deleteAllSessions(for serviceId: ServiceId, tx: DBWriteTransaction) { }
    func deleteAllSessions(for recipientUniqueId: RecipientUniqueId, tx: DBWriteTransaction) { }
    func removeAll(tx: DBWriteTransaction) { }
    func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [LibSignalClient.SessionRecord] { [] }
    func storeSession(_ record: LibSignalClient.SessionRecord, for address: ProtocolAddress, context: StoreContext) throws { }
}

#endif
