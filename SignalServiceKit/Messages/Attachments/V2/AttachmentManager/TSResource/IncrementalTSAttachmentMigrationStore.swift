//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class IncrementalTSAttachmentMigrationStore {

    public enum State: Int, Codable {
        case unstarted
        case started
        case finished

        static let key = "state"
    }

    private static var kvStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "IncrementalMessageTSAttachmentMigrator")
    }

    public static func getState(tx: SDSAnyReadTransaction) -> State {
        return (try? kvStore.getCodableValue(forKey: State.key, transaction: tx)) ?? .unstarted
    }

    public static func setState(_ state: State, tx: SDSAnyWriteTransaction) throws {
        try kvStore.setCodable(state, key: State.key, transaction: tx)
    }
}
