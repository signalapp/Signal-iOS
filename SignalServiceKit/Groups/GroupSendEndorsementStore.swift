//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
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

#if DEBUG

class MockGroupSendEndorsementStore: GroupSendEndorsementStore {
    private let combinedRecords = AtomicValue<[CombinedGroupSendEndorsementRecord]>([], lock: .init())
    private let individualRecords = AtomicValue<[IndividualGroupSendEndorsementRecord]>([], lock: .init())

    func fetchCombinedEndorsement(groupThreadId: Int64, tx: any DBReadTransaction) throws -> CombinedGroupSendEndorsementRecord? {
        return combinedRecords.update { $0.first(where: { $0.threadId == groupThreadId }) }
    }

    func fetchIndividualEndorsements(groupThreadId: Int64, tx: any DBReadTransaction) throws -> [IndividualGroupSendEndorsementRecord] {
        return individualRecords.update { $0.filter({ $0.threadId == groupThreadId }) }
    }

    func deleteEndorsements(groupThreadId: Int64, tx: any DBWriteTransaction) {
        combinedRecords.update { $0.removeAll(where: { $0.threadId == groupThreadId }) }
        individualRecords.update { $0.removeAll(where: { $0.threadId == groupThreadId }) }
    }

    func insertCombinedEndorsement(_ endorsementRecord: CombinedGroupSendEndorsementRecord, tx: any DBWriteTransaction) {
        combinedRecords.update { $0.append(endorsementRecord) }
    }

    func insertIndividualEndorsement(_ endorsementRecord: IndividualGroupSendEndorsementRecord, tx: any DBWriteTransaction) {
        individualRecords.update { $0.append(endorsementRecord) }
    }
}

#endif
