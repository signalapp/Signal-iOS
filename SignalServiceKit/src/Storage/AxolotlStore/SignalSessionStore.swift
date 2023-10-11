//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol SignalSessionStore: LibSignalClient.SessionStore {
    func mightContainSession(
        for recipient: SignalRecipient,
        tx: DBReadTransaction
    ) -> Bool

    func mergeRecipient(
        _ recipient: SignalRecipient,
        into targetRecipient: SignalRecipient,
        tx: DBWriteTransaction
    )

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
