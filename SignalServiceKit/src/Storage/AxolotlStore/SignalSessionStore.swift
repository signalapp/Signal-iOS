//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol SignalSessionStore: LibSignalClient.SessionStore {
    func containsActiveSession(
        for serviceId: ServiceId,
        deviceId: Int32,
        tx: DBReadTransaction
    ) -> Bool

    func containsActiveSession(
        forAccountId accountId: String,
        deviceId: Int32,
        tx: DBReadTransaction
    ) -> Bool

    func archiveAllSessions(
        for address: SignalServiceAddress,
        tx: DBWriteTransaction
    )

    func archiveAllSessions(
        forAccountId accountId: String,
        tx: DBWriteTransaction
    )

    func archiveSession(
        for address: SignalServiceAddress,
        deviceId: Int32,
        tx: DBWriteTransaction
    )

    func loadSession(
        for address: SignalServiceAddress,
        deviceId: Int32,
        tx: DBReadTransaction
    ) throws -> SessionRecord?

    func loadSession(
        for address: ProtocolAddress,
        context: StoreContext
    ) throws -> SessionRecord?

    func resetSessionStore(tx: DBWriteTransaction)

    func deleteAllSessions(
        for address: SignalServiceAddress,
        tx: DBWriteTransaction
    )

    // MARK: - Debug

    func printAll(tx: DBReadTransaction)

#if TESTABLE_BUILD
    func removeAll(tx: DBWriteTransaction)
#endif
}

extension SSKSessionStore: SignalSessionStore {

    public func containsActiveSession(for serviceId: ServiceId, deviceId: Int32, tx: DBReadTransaction) -> Bool {
        containsActiveSession(for: serviceId, deviceId: deviceId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func containsActiveSession(forAccountId accountId: String, deviceId: Int32, tx: DBReadTransaction) -> Bool {
        containsActiveSession(forAccountId: accountId, deviceId: deviceId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func archiveAllSessions(for address: SignalServiceAddress, tx: DBWriteTransaction) {
        archiveAllSessions(for: address, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func archiveAllSessions(forAccountId accountId: String, tx: DBWriteTransaction) {
        archiveAllSessions(forAccountId: accountId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func archiveSession(for address: SignalServiceAddress, deviceId: Int32, tx: DBWriteTransaction) {
        archiveSession(for: address, deviceId: deviceId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func loadSession(for address: SignalServiceAddress, deviceId: Int32, tx: DBReadTransaction) throws -> SessionRecord? {
        try loadSession(for: address, deviceId: deviceId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func resetSessionStore(tx: DBWriteTransaction) {
        resetSessionStore(SDSDB.shimOnlyBridge(tx))
    }

    public func deleteAllSessions(for address: SignalServiceAddress, tx: DBWriteTransaction) {
        deleteAllSessions(for: address, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func printAll(tx: DBReadTransaction) {
        printAllSessions(transaction: SDSDB.shimOnlyBridge(tx))
    }

#if TESTABLE_BUILD
    public func removeAll(tx: DBWriteTransaction) {
        removeAll(transaction: SDSDB.shimOnlyBridge(tx))
    }
#endif
}
