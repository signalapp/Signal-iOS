//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol SignalSessionStore: LibSignalClient.SessionStore {
    func containsActiveSession(
        forAccountId accountId: String,
        deviceId: UInt32,
        tx: DBReadTransaction
    ) -> Bool

    func archiveAllSessions(
        for serviceId: ServiceId,
        tx: DBWriteTransaction
    )

    /// Deprecated. Prefer the variant that accepts a ServiceId.
    func archiveAllSessions(
        for address: SignalServiceAddress,
        tx: DBWriteTransaction
    )

    func archiveSession(
        for serviceId: ServiceId,
        deviceId: UInt32,
        tx: DBWriteTransaction
    )

    func loadSession(
        for serviceId: ServiceId,
        deviceId: UInt32,
        tx: DBReadTransaction
    ) throws -> SessionRecord?

    func loadSession(
        for address: ProtocolAddress,
        context: StoreContext
    ) throws -> SessionRecord?

    func resetSessionStore(tx: DBWriteTransaction)

    func deleteAllSessions(
        for serviceId: ServiceId,
        tx: DBWriteTransaction
    )

    // MARK: - Debug

    func printAll(tx: DBReadTransaction)

#if TESTABLE_BUILD
    func removeAll(tx: DBWriteTransaction)
#endif
}

extension SSKSessionStore: SignalSessionStore {
    public func containsActiveSession(forAccountId accountId: String, deviceId: UInt32, tx: DBReadTransaction) -> Bool {
        return containsActiveSession(forAccountId: accountId, deviceId: deviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func archiveAllSessions(for serviceId: ServiceId, tx: DBWriteTransaction) {
        archiveAllSessions(for: serviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func archiveAllSessions(for address: SignalServiceAddress, tx: DBWriteTransaction) {
        archiveAllSessions(for: address, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func archiveSession(for serviceId: ServiceId, deviceId: UInt32, tx: DBWriteTransaction) {
        archiveSession(for: serviceId, deviceId: deviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func loadSession(for serviceId: ServiceId, deviceId: UInt32, tx: DBReadTransaction) throws -> SessionRecord? {
        try loadSession(for: serviceId, deviceId: deviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func resetSessionStore(tx: DBWriteTransaction) {
        resetSessionStore(SDSDB.shimOnlyBridge(tx))
    }

    public func deleteAllSessions(for serviceId: ServiceId, tx: DBWriteTransaction) {
        deleteAllSessions(for: serviceId, tx: SDSDB.shimOnlyBridge(tx))
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
