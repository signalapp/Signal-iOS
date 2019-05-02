//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

// MARK: - Any*Transaction

@objc
public class GRDBReadTransaction: NSObject {
    public let database: Database

    init(database: Database) {
        self.database = database
    }
}

// MARK: -

@objc
public class GRDBWriteTransaction: GRDBReadTransaction {
}

// MARK: -

// Type erased transactions are generated at the top level (by DatabaseStorage) and can then be
// passed through an adapter which will be backed by either YapDB or GRDB
//
// To faciliate a gradual migration to GRDB features without breaking existing Yap functionality
// there are backdoors like `transitional_yapReadTransaction` which will unwrap
// the underlying YapDatabaseRead/WriteTransaction.
@objc
public class SDSAnyReadTransaction: NSObject {
    public enum ReadTransactionType {
        case yapRead(_ transaction: YapDatabaseReadTransaction)
        case grdbRead(_ transaction: GRDBReadTransaction)
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

    public var transitional_grdbReadTransaction: GRDBReadTransaction? {
        switch readTransaction {
        case .yapRead:
            return nil
        case .grdbRead(let transaction):
            return transaction
        }
    }
}

@objc
public class SDSAnyWriteTransaction: SDSAnyReadTransaction {
    public enum WriteTransactionType {
        case yapWrite(_ transaction: YapDatabaseReadWriteTransaction)
        case grdbWrite(_ transaction: GRDBWriteTransaction)
    }

    public let writeTransaction: WriteTransactionType

    init(_ writeTransaction: WriteTransactionType) {
        self.writeTransaction = writeTransaction

        let readTransaction: ReadTransactionType
        switch writeTransaction {
        case .yapWrite(let yapWrite):
            readTransaction = ReadTransactionType.yapRead(yapWrite)
        case .grdbWrite(let transaction):
            readTransaction = ReadTransactionType.grdbRead(transaction)
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

    public var transitional_grdbWriteTransaction: GRDBWriteTransaction? {
        switch writeTransaction {
        case .yapWrite:
            return nil
        case .grdbWrite(let transaction):
            return transaction
        }
    }
}

// MARK: -

@objc
public extension YapDatabaseReadTransaction {
    @objc
    var asAnyRead: SDSAnyReadTransaction {
        return SDSAnyReadTransaction(transitional_yapReadTransaction: self)
    }
}

// MARK: -

@objc
public extension YapDatabaseReadWriteTransaction {
    @objc
    var asAnyWrite: SDSAnyWriteTransaction {
        return SDSAnyWriteTransaction(transitional_yapWriteTransaction: self)
    }
}
