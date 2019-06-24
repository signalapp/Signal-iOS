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

// MARK: -

public extension SDSModel {
    func sdsSave(saveMode: SDSSaveMode, transaction: SDSAnyWriteTransaction) {
        if saveMode == .insert {
            anyWillInsert(with: transaction)
        }

        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            ydb_save(with: ydbTransaction)
        case .grdbWrite(let grdbTransaction):
            do {
                let record = try asRecord()
                record.sdsSave(saveMode: saveMode, transaction: grdbTransaction)
            } catch {
                owsFail("Write failed: \(error)")
            }
        }

        if saveMode == .insert {
            anyDidInsert(with: transaction)
        }
    }
}

// MARK: -

public extension TableRecord {
    static func ows_fetchCount(_ db: Database) -> UInt {
        do {
            let result = try fetchCount(db)
            guard result >= 0 else {
                owsFailDebug("Invalid result: \(result)")
                return 0
            }
            guard result <= UInt.max else {
                owsFailDebug("Invalid result: \(result)")
                return UInt.max
            }
            return UInt(result)
        } catch {
            owsFailDebug("Read failed: \(error)")
            return 0
        }
    }
}
