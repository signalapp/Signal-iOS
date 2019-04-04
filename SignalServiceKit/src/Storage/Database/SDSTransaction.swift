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

    public let transaction: ReadTransactionType

    init(_ transaction: ReadTransactionType) {
        self.transaction = transaction
    }

    // MARK: Transitional Methods

    // Useful to delineate where we're using SDSAnyReadTransaction if a specific
    // feature hasn't been migrated and still requires a YapDatabaseReadTransaction

    @objc
    public init(transitional_yapTransaction: YapDatabaseReadTransaction) {
        self.transaction = .yapRead(transitional_yapTransaction)
    }

    @objc
    public var transitional_yapTransaction: YapDatabaseReadTransaction? {
        switch transaction {
        case .yapRead(let yapRead):
            return yapRead
        case .grdbRead:
            return nil
        }
    }
}

@objc
public class SDSAnyWriteTransaction: NSObject {
    public enum WriteTransactionType {
        case yapWrite(_ transaction: YapDatabaseReadWriteTransaction)
        case grdbWrite(_ transaction: Database)
    }

    let transaction: WriteTransactionType

    init(_ transaction: WriteTransactionType) {
        self.transaction = transaction
    }

    // MARK: Transitional Methods

    // Useful to delineate where we're using SDSAnyReadTransaction if a specific
    // feature hasn't been migrated and still requires a YapDatabaseReadTransaction

    @objc
    public init(transitional_yapTransaction: YapDatabaseReadWriteTransaction) {
        self.transaction = .yapWrite(transitional_yapTransaction)
    }

    @objc
    public var transitional_yapTransaction: YapDatabaseReadWriteTransaction? {
        switch transaction {
        case .yapWrite(let yapWrite):
            return yapWrite
        case .grdbWrite:
            return nil
        }
    }
}
