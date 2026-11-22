//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// Reads and writes account capabilities as of their last profile fetch.
public struct RecipientCapabilityStore {
    public init() {}

    /// Returns `nil` if we haven't stored this capability for the recipient.
    public func isEnabled(
        capability: RecipientCapability,
        recipientRowId: SignalRecipient.RowId,
        tx: DBReadTransaction,
    ) -> Bool? {
        return failIfThrows {
            try RecipientCapabilityRecord
                .filter(RecipientCapabilityRecord.CodingKeys.recipientRowId == recipientRowId)
                .filter(RecipientCapabilityRecord.CodingKeys.capability == capability.rawValue)
                .fetchOne(tx.database)?
                .isEnabled
        }
    }

    /// Replaces all of the recipient's stored capabilities. Capabilities
    /// missing from the `capabilities` dictionary become unknown.
    func setCapabilities(
        _ capabilities: [RecipientCapability: Bool],
        recipientRowId: SignalRecipient.RowId,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try RecipientCapabilityRecord
                .filter(RecipientCapabilityRecord.CodingKeys.recipientRowId == recipientRowId)
                .deleteAll(tx.database)

            for (capability, isEnabled) in capabilities where capability.isStoredPerRecipient {
                try RecipientCapabilityRecord(
                    recipientRowId: recipientRowId,
                    capability: capability,
                    isEnabled: isEnabled,
                ).insert(tx.database)
            }
        }
    }
}
