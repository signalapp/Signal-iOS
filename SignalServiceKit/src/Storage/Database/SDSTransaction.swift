//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

// MARK: - Any*Transaction

// Type erased transactions are generated at the top level (by DatabaseStorage) and can then be
// passed through an adapter which will be backed by either YapDB or GRDB
//
// To faciliate a gradual migration to GRDB features without breaking existing Yap functionality
// there are backdoors like `transitional_yapTransaction` which will unwrap
// the underlying YapDatabaseRead/WriteTransaction.
@objc
public class SDSAnyReadTransaction: NSObject {
    public enum ReadTransactionType {
        case yapRead(_ transaction: YapDatabaseReadTransaction)
        case grdbRead(_ transaction: Database)
    }

    public let readTransaction: ReadTransactionType

    init(_ readTransaction: ReadTransactionType) {
        self.readTransaction = readTransaction
    }

    // MARK: Transitional Methods

    // Useful to delineate where we're using SDSAnyReadTransaction if a specific
    // feature hasn't been migrated and still requires a YapDatabaseReadTransaction

    @objc
    public init(transitional_yapReadTransaction: YapDatabaseReadTransaction) {
        self.readTransaction = .yapRead(transitional_yapReadTransaction)
    }

    @objc
    public var transitional_yapReadTransaction: YapDatabaseReadTransaction? {
        switch readTransaction {
        case .yapRead(let yapRead):
            return yapRead
        case .grdbRead:
            return nil
        }
    }

    public var transitional_grdbReadTransaction: Database? {
        switch readTransaction {
        case .yapRead:
            return nil
        case .grdbRead(let database):
            return database
        }
    }
}

@objc
public class SDSAnyWriteTransaction: SDSAnyReadTransaction {
    public enum WriteTransactionType {
        case yapWrite(_ transaction: YapDatabaseReadWriteTransaction)
        case grdbWrite(_ transaction: Database)
    }

    let writeTransaction: WriteTransactionType

    init(_ writeTransaction: WriteTransactionType) {
        self.writeTransaction = writeTransaction

        let readTransaction: ReadTransactionType
        switch writeTransaction {
        case .yapWrite(let yapWrite):
            readTransaction = ReadTransactionType.yapRead(yapWrite)
        case .grdbWrite(let database):
            readTransaction = ReadTransactionType.grdbRead(database)
        }

        super.init(readTransaction)
    }

    // MARK: Transitional Methods

    // Useful to delineate where we're using SDSAnyReadTransaction if a specific
    // feature hasn't been migrated and still requires a YapDatabaseReadTransaction

    @objc
    public init(transitional_yapWriteTransaction: YapDatabaseReadWriteTransaction) {
        self.writeTransaction = .yapWrite(transitional_yapWriteTransaction)

        super.init(transitional_yapReadTransaction: transitional_yapWriteTransaction)
    }

    @objc
    public var transitional_yapWriteTransaction: YapDatabaseReadWriteTransaction? {
        switch writeTransaction {
        case .yapWrite(let yapWrite):
            return yapWrite
        case .grdbWrite:
            return nil
        }
    }

    public var transitional_grdbWriteTransaction: Database? {
        switch writeTransaction {
        case .yapWrite:
            return nil
        case .grdbWrite(let database):
            return database
        }
    }
}
