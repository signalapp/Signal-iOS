//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public struct GroupSendEndorsementStore {
    func saveEndorsements(
        groupRowId: GroupRecord.RowId,
        expiration: Date,
        combinedEndorsement: GroupSendEndorsement,
        individualEndorsements: [(recipientId: Int64, individualEndorsement: GroupSendEndorsement)],
        tx: DBWriteTransaction,
    ) {
        deleteEndorsements(groupRowId: groupRowId, tx: tx)
        insertCombinedEndorsement(CombinedGroupSendEndorsementRecord(
            groupRowId: groupRowId,
            endorsement: combinedEndorsement.serialize(),
            expiration: expiration,
        ), tx: tx)
        for (recipientId, individualEndorsement) in individualEndorsements {
            insertIndividualEndorsement(IndividualGroupSendEndorsementRecord(
                groupRowId: groupRowId,
                recipientId: recipientId,
                endorsement: individualEndorsement.serialize(),
            ), tx: tx)
        }
    }

    func fetchCombinedEndorsement(groupRowId: GroupRecord.RowId, tx: DBReadTransaction) -> CombinedGroupSendEndorsementRecord? {
        return failIfThrows {
            return try CombinedGroupSendEndorsementRecord.fetchOne(tx.database, key: groupRowId)
        }
    }

    public func fetchNextExpiringCombinedEndorsement(tx: DBReadTransaction) -> CombinedGroupSendEndorsementRecord? {
        return failIfThrows {
            return try CombinedGroupSendEndorsementRecord
                .order(Column(CombinedGroupSendEndorsementRecord.CodingKeys.expiration).asc)
                .fetchOne(tx.database)
        }
    }

    func fetchIndividualEndorsements(groupRowId: CombinedGroupSendEndorsementRecord.RowId, tx: DBReadTransaction) -> [IndividualGroupSendEndorsementRecord] {
        return failIfThrows {
            return try IndividualGroupSendEndorsementRecord
                .filter(Column(IndividualGroupSendEndorsementRecord.CodingKeys.groupRowId) == groupRowId)
                .fetchAll(tx.database)
        }
    }

    func fetchIndividualEndorsement(groupRowId: CombinedGroupSendEndorsementRecord.RowId, recipientId: SignalRecipient.RowId, tx: DBReadTransaction) -> IndividualGroupSendEndorsementRecord? {
        return failIfThrows {
            return try IndividualGroupSendEndorsementRecord
                .filter(Column(IndividualGroupSendEndorsementRecord.CodingKeys.groupRowId) == groupRowId)
                .filter(Column(IndividualGroupSendEndorsementRecord.CodingKeys.recipientId) == recipientId)
                .fetchOne(tx.database)
        }
    }

    public func deleteEndorsements(groupRowId: CombinedGroupSendEndorsementRecord.RowId, tx: DBWriteTransaction) {
        failIfThrows {
            try CombinedGroupSendEndorsementRecord.deleteOne(tx.database, key: groupRowId)
        }
    }

    func insertCombinedEndorsement(_ endorsementRecord: CombinedGroupSendEndorsementRecord, tx: DBWriteTransaction) {
        failIfThrows {
            try endorsementRecord.insert(tx.database)
        }
    }

    func insertIndividualEndorsement(_ endorsementRecord: IndividualGroupSendEndorsementRecord, tx: DBWriteTransaction) {
        failIfThrows {
            try endorsementRecord.insert(tx.database)
        }
    }
}
