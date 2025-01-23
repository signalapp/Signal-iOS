//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

protocol GroupSendEndorsementStore {
    func fetchCombinedEndorsement(groupThreadId: Int64, tx: any DBReadTransaction) throws -> CombinedGroupSendEndorsementRecord?
    func fetchIndividualEndorsements(groupThreadId: Int64, tx: any DBReadTransaction) throws -> [IndividualGroupSendEndorsementRecord]
    func deleteEndorsements(groupThreadId: Int64, tx: any DBWriteTransaction)
    func insertCombinedEndorsement(_ endorsementRecord: CombinedGroupSendEndorsementRecord, tx: any DBWriteTransaction)
    func insertIndividualEndorsement(_ endorsementRecord: IndividualGroupSendEndorsementRecord, tx: any DBWriteTransaction)
}

extension GroupSendEndorsementStore {
    func saveEndorsements(
        groupThreadId: Int64,
        expiration: Date,
        combinedEndorsement: GroupSendEndorsement,
        individualEndorsements: [(recipientId: Int64, individualEndorsement: GroupSendEndorsement)],
        tx: any DBWriteTransaction
    ) {
        deleteEndorsements(groupThreadId: groupThreadId, tx: tx)
        insertCombinedEndorsement(CombinedGroupSendEndorsementRecord(
            threadId: groupThreadId,
            endorsement: combinedEndorsement.serialize().asData,
            expiration: expiration
        ), tx: tx)
        for (recipientId, individualEndorsement) in individualEndorsements {
            insertIndividualEndorsement(IndividualGroupSendEndorsementRecord(
                threadId: groupThreadId,
                recipientId: recipientId,
                endorsement: individualEndorsement.serialize().asData
            ), tx: tx)
        }
    }
}

class GroupSendEndorsementStoreImpl: GroupSendEndorsementStore {
    func fetchCombinedEndorsement(groupThreadId: Int64, tx: any DBReadTransaction) throws -> CombinedGroupSendEndorsementRecord? {
        do {
            return try CombinedGroupSendEndorsementRecord.fetchOne(tx.databaseConnection, key: groupThreadId)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func fetchIndividualEndorsements(groupThreadId: Int64, tx: any DBReadTransaction) throws -> [IndividualGroupSendEndorsementRecord] {
        do {
            return try IndividualGroupSendEndorsementRecord
                .filter(Column(IndividualGroupSendEndorsementRecord.CodingKeys.threadId) == groupThreadId)
                .fetchAll(tx.databaseConnection)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func deleteEndorsements(groupThreadId: Int64, tx: any DBWriteTransaction) {
        do {
            try CombinedGroupSendEndorsementRecord.deleteOne(tx.databaseConnection, key: groupThreadId)
        } catch {
            owsFail("Couldn't delete records: \(error.grdbErrorForLogging)")
        }
    }

    func insertCombinedEndorsement(_ endorsementRecord: CombinedGroupSendEndorsementRecord, tx: any DBWriteTransaction) {
        do {
            try endorsementRecord.insert(tx.databaseConnection)
        } catch {
            owsFail("Couldn't insert record: \(error.grdbErrorForLogging)")
        }
    }

    func insertIndividualEndorsement(_ endorsementRecord: IndividualGroupSendEndorsementRecord, tx: any DBWriteTransaction) {
        do {
            try endorsementRecord.insert(tx.databaseConnection)
        } catch {
            owsFail("Couldn't insert record: \(error.grdbErrorForLogging)")
        }
    }
}
