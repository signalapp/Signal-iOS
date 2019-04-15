//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

public protocol SDSSerializable {
    var serializer: SDSSerializer { get }
}

public protocol SDSSerializer {
    func serializableColumnTableMetadata() -> SDSTableMetadata

    func insertColumnNames() -> [String]

    func insertColumnValues() -> [DatabaseValueConvertible]

    func updateColumnNames() -> [String]

    func updateColumnValues() -> [DatabaseValueConvertible]

    func uniqueIdColumnName() -> String

    func uniqueIdColumnValue() -> DatabaseValueConvertible
}
