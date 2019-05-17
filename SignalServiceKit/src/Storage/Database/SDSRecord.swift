//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

public protocol SDSRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64? { get set }
    var uniqueId: String { get }
}

public extension SDSRecord {
    mutating func didInsert(with rowID: Int64, for column: String?) {
        guard id == nil else {
            owsFailDebug("Inserting record which already has id.")
            return
        }
        id = rowID
    }
}
