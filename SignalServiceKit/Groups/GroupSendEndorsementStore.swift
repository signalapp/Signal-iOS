//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

protocol GroupSendEndorsementStore {
    func fetchCombinedEndorsement(groupThreadId: Int64, tx: DBReadTransaction) throws -> CombinedGroupSendEndorsementRecord?
    func fetchIndividualEndorsements(groupThreadId: Int64, tx: DBReadTransaction) throws -> [IndividualGroupSendEndorsementRecord]
    func fetchIndividualEndorsement(groupThreadId: Int64, recipientId: SignalRecipient.RowId, tx: DBReadTransaction) throws -> IndividualGroupSendEndorsementRecord?
    func deleteEndorsements(groupThreadId: Int64, tx: DBWriteTransaction)
    func insertCombinedEndorsement(_ endorsementRecord: CombinedGroupSendEndorsementRecord, tx: DBWriteTransaction)
    func insertIndividualEndorsement(_ endorsementRecord: IndividualGroupSendEndorsementRecord, tx: DBWriteTransaction)
}

extension GroupSendEndorsementStore {
    func saveEndorsements(
        groupThreadId: Int64,
        expiration: Date,
        combinedEndorsement: GroupSendEndorsement,
        individualEndorsements: [(recipientId: Int64, individualEndorsement: GroupSendEndorsement)],
        tx: DBWriteTransaction,
    ) {
        deleteEndorsements(groupThreadId: groupThreadId, tx: tx)
        insertCombinedEndorsement(CombinedGroupSendEndorsementRecord(
            threadId: groupThreadId,
            endorsement: combinedEndorsement.serialize(),
            expiration: expiration,
        ), tx: tx)
        for (recipientId, individualEndorsement) in individualEndorsements {
            insertIndividualEndorsement(IndividualGroupSendEndorsementRecord(
                threadId: groupThreadId,
                recipientId: recipientId,
                endorsement: individualEndorsement.serialize(),
            ), tx: tx)
        }
    }
}

class GroupSendEndorsementStoreImpl: GroupSendEndorsementStore {
    func fetchCombinedEndorsement(groupThreadId: Int64, tx: DBReadTransaction) throws -> CombinedGroupSendEndorsementRecord? {
        do {
            return try CombinedGroupSendEndorsementRecord.fetchOne(tx.database, key: groupThreadId)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func fetchIndividualEndorsements(groupThreadId: Int64, tx: DBReadTransaction) throws -> [IndividualGroupSendEndorsementRecord] {
        do {
            return try IndividualGroupSendEndorsementRecord
                .filter(Column(IndividualGroupSendEndorsementRecord.CodingKeys.threadId) == groupThreadId)
                .fetchAll(tx.database)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func fetchIndividualEndorsement(groupThreadId: Int64, recipientId: SignalRecipient.RowId, tx: DBReadTransaction) throws -> IndividualGroupSendEndorsementRecord? {
        do {
            return try IndividualGroupSendEndorsementRecord
                .filter(Column(IndividualGroupSendEndorsementRecord.CodingKeys.threadId) == groupThreadId)
                .filter(Column(IndividualGroupSendEndorsementRecord.CodingKeys.recipientId) == recipientId)
                .fetchOne(tx.database)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func deleteEndorsements(groupThreadId: Int64, tx: DBWriteTransaction) {
        do {
            try CombinedGroupSendEndorsementRecord.deleteOne(tx.database, key: groupThreadId)
        } catch {
            owsFail("Couldn't delete records: \(error.grdbErrorForLogging)")
        }
    }

    func insertCombinedEndorsement(_ endorsementRecord: CombinedGroupSendEndorsementRecord, tx: DBWriteTransaction) {
        do {
            try endorsementRecord.insert(tx.database)
        } catch {
            owsFail("Couldn't insert record: \(error.grdbErrorForLogging)")
        }
    }

    func insertIndividualEndorsement(_ endorsementRecord: IndividualGroupSendEndorsementRecord, tx: DBWriteTransaction) {
        do {
            try endorsementRecord.insert(tx.database)
        } catch {
            owsFail("Couldn't insert record: \(error.grdbErrorForLogging)")
        }
    }
}
