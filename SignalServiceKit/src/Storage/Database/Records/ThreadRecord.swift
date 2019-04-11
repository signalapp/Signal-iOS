//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

// This Temporary Model Adapter will likely be replaced by the more thourough deserialization
// logic @cmchen is working on. For now we have a crude minimal way of deserializing the necessary
// information to get a migration scaffolded and message windowing working for GRDB.

public extension TSThread {
    class func fromRecord(_ record: ThreadRecord) -> TSThread {
        let archivedAsOfMessageSortId: NSNumber?
        if let value = record.archivedAsOfMessageSortId {
            archivedAsOfMessageSortId = NSNumber(value: value)
        } else {
            archivedAsOfMessageSortId = nil
        }

        switch record.recordType {
        case .contactThread:
            return TSContactThread(uniqueId: record.uniqueId,
                                   archivalDate: record.archivalDate,
                                   archivedAsOfMessageSortId: archivedAsOfMessageSortId,
                                   conversationColorName: record.conversationColorName,
                                   creationDate: record.creationDate,
                                   isArchivedByLegacyTimestampForSorting: record.isArchivedByLegacyTimestampForSorting,
                                   lastMessageDate: record.lastMessageDate,
                                   messageDraft: record.messageDraft,
                                   mutedUntilDate: record.mutedUntilDate,
                                   shouldThreadBeVisible: record.shouldThreadBeVisible,
                                   hasDismissedOffers: record.hasDismissedOffers ?? false)
        case .groupThread:
            guard let serializedGroupModel = record.groupModel else {
                owsFail("serializedGroupModel was unexpectedly nil")
            }

            guard let groupModel: TSGroupModel = try? SDSDeserializer.unarchive(serializedGroupModel) else {
                owsFail("invalid record")
            }

            return TSGroupThread(uniqueId: record.uniqueId,
                                 archivalDate: record.archivalDate,
                                 archivedAsOfMessageSortId: archivedAsOfMessageSortId,
                                 conversationColorName: record.conversationColorName,
                                 creationDate: record.creationDate,
                                 isArchivedByLegacyTimestampForSorting: record.isArchivedByLegacyTimestampForSorting,
                                 lastMessageDate: record.lastMessageDate,
                                 messageDraft: record.messageDraft,
                                 mutedUntilDate: record.mutedUntilDate,
                                 shouldThreadBeVisible: record.shouldThreadBeVisible,
                                 groupModel: groupModel)
        default:
            owsFail("thread record shouldn't be saved with non-thread recordType: \(record.recordType)")
        }
    }
}

public enum ThreadRecordType: Int {
    case contact = 1
    case group = 2
}

extension ThreadRecordType: Codable { }
extension ThreadRecordType: DatabaseValueConvertible { }

public struct ThreadRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName: String = TSThreadSerializer.table.tableName

    public let id: Int
    public let recordType: SDSRecordType
    public let uniqueId: String
    public let archivalDate: Date?
    public let archivedAsOfMessageSortId: UInt64?
    public let conversationColorName: String
    public let creationDate: Date
    public let isArchivedByLegacyTimestampForSorting: Bool
    public let lastMessageDate: Date?
    public let messageDraft: String?
    public let mutedUntilDate: Date?
    public let shouldThreadBeVisible: Bool
    public let groupModel: Data?
    public let hasDismissedOffers: Bool?

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case archivalDate
        case archivedAsOfMessageSortId
        case conversationColorName
        case creationDate
        case isArchivedByLegacyTimestampForSorting
        case lastMessageDate
        case messageDraft
        case mutedUntilDate
        case shouldThreadBeVisible
        case groupModel
        case hasDismissedOffers
    }

    public static func columnName(_ column: ThreadRecord.CodingKeys) -> String {
        return column.rawValue
    }
}

extension SDSRecordType: Codable { }
