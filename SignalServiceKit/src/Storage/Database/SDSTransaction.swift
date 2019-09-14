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

    @objc
    public var asAnyRead: SDSAnyReadTransaction {
        return SDSAnyReadTransaction(.grdbRead(self))
    }
}

// MARK: -

@objc
public class GRDBWriteTransaction: GRDBReadTransaction {
    @objc
    public var asAnyWrite: SDSAnyWriteTransaction {
        return SDSAnyWriteTransaction(.grdbWrite(self))
    }

    internal var completions: [(DispatchQueue, () -> Void)] = []

    @objc
    public func addCompletion(queue: DispatchQueue, block: @escaping () -> Void) {
        completions.append((queue, block))
    }
}

// MARK: -

// Type erased transactions are generated at the top level (by DatabaseStorage) and can then be
// passed through an adapter which will be backed by either YapDB or GRDB
//
// To faciliate a gradual migration to GRDB features without breaking existing Yap functionality
// there are backdoors like `transitional_yapReadTransaction` which will unwrap
// the underlying YapDatabaseRead/WriteTransaction.
@objc
public class SDSAnyReadTransaction: NSObject, SPKProtocolReadContext {
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
}

@objc
public class SDSAnyWriteTransaction: SDSAnyReadTransaction, SPKProtocolWriteContext {
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
        case .grdbWrite(let grdbWrite):
            readTransaction = ReadTransactionType.grdbRead(grdbWrite)
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

    // GRDB TODO: Remove this method.
    @objc
    public var transitional_yapWriteTransaction: YapDatabaseReadWriteTransaction? {
        switch writeTransaction {
        case .yapWrite(let yapWrite):
            return yapWrite
        case .grdbWrite:
            return nil
        }
    }

    // Objective-C doesn't honor default arguments.
    @objc
    public func addCompletion(block: @escaping () -> Void) {
        addCompletion(queue: DispatchQueue.main, block: block)
    }

    @objc
    public func addCompletion(queue: DispatchQueue = DispatchQueue.main, block: @escaping () -> Void) {
        switch writeTransaction {
        case .yapWrite(let yapWrite):
            yapWrite.addCompletionQueue(queue, completionBlock: block)
        case .grdbWrite(let grdbWrite):
            grdbWrite.addCompletion(queue: queue, block: block)
        }
    }
}

// MARK: -

@objc
public extension YapDatabaseReadTransaction {
    var asAnyRead: SDSAnyReadTransaction {
        return SDSAnyReadTransaction(transitional_yapReadTransaction: self)
    }
}

// MARK: -

@objc
public extension YapDatabaseReadWriteTransaction {
    var asAnyWrite: SDSAnyWriteTransaction {
        return SDSAnyWriteTransaction(transitional_yapWriteTransaction: self)
    }
}

// MARK: - Convenience Methods

public extension GRDBWriteTransaction {
    // This has significant perf benefits over database.execute()
    // for queries that we perform repeatedly.
    func executeWithCachedStatement(sql: String,
                                    arguments: StatementArguments = StatementArguments()) {
        do {
            let statement = try database.cachedUpdateStatement(sql: sql)
            // TODO: We could use setArgumentsWithValidation for more safety.
            statement.unsafeSetArguments(arguments)
            try statement.execute()
        } catch {
            owsFail("Error: \(error)")
        }
    }
}
