//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

public protocol SDSModel: TSYapDatabaseObject {
    func asRecord() throws -> SDSRecord

    var serializer: SDSSerializer { get }

    func anyInsert(transaction: SDSAnyWriteTransaction)
}

public extension SDSModel {
    func sdsSave(saveMode: SDSSaveMode, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            save(with: ydbTransaction)
        case .grdbWrite(let grdbTransaction):
            do {
                let record = try asRecord()
                record.sdsSave(saveMode: saveMode, transaction: grdbTransaction)
            } catch {
                owsFail("Write failed: \(error)")
            }
        }
    }
}
