//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

// TODO: We need to revise this.
public enum SDSColumnType {
    case unicodeString
    case blob
    case bool
    case int
    case int64
    case double
    case primaryKey
}

public struct SDSColumnMetadata {

    public let columnName: String
    public let columnType: SDSColumnType
    public let isOptional: Bool
    public let isUnique: Bool

    public init(columnName: String, columnType: SDSColumnType, isOptional: Bool = false, isUnique: Bool = false) {
        self.columnName = columnName
        self.columnType = columnType
        self.isOptional = isOptional
        self.isUnique = isUnique
    }
}

// MARK: -

public struct SDSTableMetadata {

    public let tableName: String
    public let columns: [SDSColumnMetadata]

    public init(tableName: String, columns: [SDSColumnMetadata]) {
        self.tableName = tableName
        self.columns = columns
    }
}
