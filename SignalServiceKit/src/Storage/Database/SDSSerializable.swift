//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

@objc
public protocol SDSSerializable {
    func serializableColumnTableMetadata() -> SDSTableMetadata

    func insertColumnNames() -> [String]

    // In practice, these values should all be DatabaseValueConvertible,
    // but that protocol is not @objc.
    func insertColumnValues() -> [Any]

    func updateColumnNames() -> [String]

    // In practice, these values should all be DatabaseValueConvertible,
    // but that protocol is not @objc.
    func updateColumnValues() -> [Any]

    func uniqueIdColumnName() -> String

    // In practice, these values should all be DatabaseValueConvertible,
    // but that protocol is not @objc.
    func uniqueIdColumnValue() -> Any
}
