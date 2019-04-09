//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

// This Temporary Model Adapter will likely be replaced by the more thourough deserialization
// logic @cmchen is working on. For now we have a crude minimal way of deserializing the necessary
// information to get a migration scaffolded and message windowing working for GRDB.

public extension TSThread {
    class func fromRecord(_ threadRecord: ThreadRecord) -> TSThread {
        switch threadRecord.threadType {
        case .contact:
            return TSContactThread(uniqueId: threadRecord.uniqueId)
        case .group:
            fatalError("TODO")
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
    public static let databaseTableName: String = "threads"

    public let id: Int
    public let uniqueId: String
    public let shouldBeVisible: Bool
    public let creationDate: Date
    public let threadType: ThreadRecordType

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id, uniqueId, shouldBeVisible, creationDate, threadType
    }

    public static func columnName(_ column: ThreadRecord.CodingKeys) -> String {
        return column.rawValue
    }
}
