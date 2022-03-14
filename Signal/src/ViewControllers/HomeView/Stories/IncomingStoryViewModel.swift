//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

struct IncomingStoryViewModel: Dependencies {
    let context: StoryContext

    let records: [StoryMessageRecord]
    let recordIds: [Int64]
    let hasUnviewedRecords: Bool
    enum Attachment {
        case file(TSAttachment)
        case text(TextAttachment)
        case missing
    }
    let latestRecordAttachment: Attachment
    let latestRecordHasReplies: Bool
    let latestRecordName: String
    let latestRecordTimestamp: UInt64

    let latestRecordAvatarDataSource: ConversationAvatarDataSource

    init(records: [StoryMessageRecord], transaction: SDSAnyReadTransaction) throws {
        let sortedFilteredRecords = records.lazy.filter { $0.direction == .incoming }.sorted { $0.timestamp > $1.timestamp }
        self.records = sortedFilteredRecords
        self.recordIds = sortedFilteredRecords.compactMap { $0.id }
        self.hasUnviewedRecords = sortedFilteredRecords.reduce(false, { partialResult, record in
            switch record.manifest {
            case .incoming(_, let viewed):
                return partialResult || !viewed
            case .outgoing:
                owsFailDebug("Unexpected record type")
                return partialResult
            }
        })

        guard let latestRecord = sortedFilteredRecords.first else {
            throw OWSAssertionError("At least one record is required.")
        }

        self.context = latestRecord.context

        if let groupId = latestRecord.groupId {
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing group thread for group story")
            }
            let authorShortName = Self.contactsManager.shortDisplayName(
                for: latestRecord.authorAddress,
                transaction: transaction
            )
            let nameFormat = NSLocalizedString(
                "GROUP_STORY_NAME_FORMAT",
                comment: "Name for a group story on the stories list. Embeds {author's name}, {group name}")
            latestRecordName = String(format: nameFormat, authorShortName, groupThread.groupNameOrDefault)
            latestRecordAvatarDataSource = .thread(groupThread)
        } else {
            latestRecordName = Self.contactsManager.displayName(
                for: latestRecord.authorAddress,
                transaction: transaction
            )
            latestRecordAvatarDataSource = .address(latestRecord.authorAddress)
        }

        switch latestRecord.attachment {
        case .file(let attachmentId):
            guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
                owsFailDebug("Unexpectedly missing attachment for story")
                latestRecordAttachment = .missing
                break
            }
            latestRecordAttachment = .file(attachment)
        case .text(let attachment):
            latestRecordAttachment = .text(attachment)
        }

        latestRecordHasReplies = false // TODO: replies
        latestRecordTimestamp = latestRecord.timestamp
    }

    func copy(updatedRecords: [StoryMessageRecord], deletedRecordIds: [Int64], transaction: SDSAnyReadTransaction) throws -> Self? {
        var updatedRecords = updatedRecords
        let records = self.records.lazy
            .filter { !deletedRecordIds.contains($0.id ?? 0) }
            .map { oldRecord in
                if let idx = updatedRecords.firstIndex(where: { $0.id == oldRecord.id }) {
                    return updatedRecords.remove(at: idx)
                } else {
                    return oldRecord
                }
            } + updatedRecords
        guard !records.isEmpty else { return nil }
        return try .init(records: records, transaction: transaction)
    }
}

extension StoryContext: BatchUpdateValue {
    public var batchUpdateId: String {
        switch self {
        case .groupId(let data):
            return data.hexadecimalString
        case .authorUuid(let uuid):
            return uuid.uuidString
        case .none:
            owsFailDebug("Unexpected StoryContext for batch update")
            return "none"
        }
    }
    public var logSafeDescription: String { batchUpdateId }
}
