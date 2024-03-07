//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public protocol SearchableNameIndexer {
    /// Searches for `searchText` in the FTS index.
    func search(
        for searchText: String,
        maxResults: Int,
        tx: DBReadTransaction,
        block: (_ indexableName: any IndexableName) throws -> Void
    ) rethrows

    /// Inserts `indexableName` into the FTS index.
    func insert(_ indexableName: IndexableName, tx: DBWriteTransaction)

    /// Updates `indexableName` in the FTS index.
    ///
    /// This will remove `indexableName` if it has no indexable content.
    func update(_ indexableName: IndexableName, tx: DBWriteTransaction)

    /// Removes `indexableName` from the FTS index.
    func delete(_ indexableName: IndexableName, tx: DBWriteTransaction)

    /// Inserts every SearchableName into the index.
    ///
    /// The index must be empty when this method is called.
    func indexEverything(tx: DBWriteTransaction)
}

public class SearchableNameIndexerImpl: SearchableNameIndexer {
    private let threadStore: any ThreadStore
    private let signalAccountStore: any SignalAccountStore
    private let userProfileStore: any UserProfileStore
    private let signalRecipientStore: any RecipientDatabaseTable
    private let usernameLookupRecordStore: any UsernameLookupRecordStore

    private let dbForReadTx: (DBReadTransaction) -> Database
    private let dbForWriteTx: (DBWriteTransaction) -> Database

    public enum Constants {
        public static let databaseTableName = "SearchableName"
        public static let databaseTableNameFTS = "SearchableNameFTS"
    }

    public init(
        threadStore: any ThreadStore,
        signalAccountStore: any SignalAccountStore,
        userProfileStore: any UserProfileStore,
        signalRecipientStore: any RecipientDatabaseTable,
        usernameLookupRecordStore: any UsernameLookupRecordStore,
        dbForReadTx: @escaping (DBReadTransaction) -> Database,
        dbForWriteTx: @escaping (DBWriteTransaction) -> Database
    ) {
        self.threadStore = threadStore
        self.signalAccountStore = signalAccountStore
        self.userProfileStore = userProfileStore
        self.signalRecipientStore = signalRecipientStore
        self.usernameLookupRecordStore = usernameLookupRecordStore
        self.dbForReadTx = dbForReadTx
        self.dbForWriteTx = dbForWriteTx
    }

    // MARK: - Search

    public func search(
        for searchText: String,
        maxResults: Int,
        tx: DBReadTransaction,
        block: (_ indexableName: IndexableName) throws -> Void
    ) rethrows {
        let query = FullTextSearchIndexer.buildQuery(for: searchText)
        if query.isEmpty {
            return
        }
        let cursor: RowCursor
        do {
            cursor = try Row.fetchCursor(
                dbForReadTx(tx),
                sql: """
                SELECT
                    "\(Constants.databaseTableName)"."\(IdentifierColumnName.threadId.rawValue)",
                    "\(Constants.databaseTableName)"."\(IdentifierColumnName.signalAccountId.rawValue)",
                    "\(Constants.databaseTableName)"."\(IdentifierColumnName.userProfileId.rawValue)",
                    "\(Constants.databaseTableName)"."\(IdentifierColumnName.signalRecipientId.rawValue)",
                    "\(Constants.databaseTableName)"."\(IdentifierColumnName.usernameLookupRecordId.rawValue)"
                FROM "\(Constants.databaseTableNameFTS)"
                LEFT JOIN "\(Constants.databaseTableName)"
                    ON "\(Constants.databaseTableName)".rowId = "\(Constants.databaseTableNameFTS)".rowId
                WHERE "\(Constants.databaseTableNameFTS)"."value" MATCH ?
                ORDER BY rank
                LIMIT \(maxResults)
                """,
                arguments: [query]
            )
        } catch {
            Logger.warn("Couldn't search for names: \(error.grdbErrorForLogging)")
            return
        }
        while true {
            let identifier: IndexableNameIdentifier
            do {
                guard let row = try cursor.next() else {
                    break
                }
                if let threadId = (row[0] as Int64?) {
                    identifier = .tsThread(threadId)
                } else if let signalAccountId = (row[1] as Int64?) {
                    identifier = .signalAccount(signalAccountId)
                } else if let userProfileId = (row[2] as Int64?) {
                    identifier = .userProfile(userProfileId)
                } else if let signalRecipientId = (row[3] as Int64?) {
                    identifier = .signalRecipient(signalRecipientId)
                } else if let usernameLookupRecordId = (row[4] as Data?).flatMap({ try? Aci.parseFrom(serviceIdBinary: $0) }) {
                    identifier = .usernameLookupRecord(usernameLookupRecordId)
                } else {
                    owsFailDebug("Couldn't find identifier for SearchableName")
                    continue
                }
            } catch {
                Logger.warn("Couldn't search for names: \(error.grdbErrorForLogging)")
                return
            }
            guard let indexableName = fetchIndexableName(for: identifier, tx: tx) else {
                owsFailDebug("Couldn't find IndexableName for SearchableName")
                continue
            }
            try block(indexableName)
        }
    }

    private func fetchIndexableName(for identifier: IndexableNameIdentifier, tx: DBReadTransaction) -> (any IndexableName)? {
        switch identifier {
        case .tsThread(let value):
            return threadStore.fetchThread(rowId: value, tx: tx)
        case .signalAccount(let value):
            return signalAccountStore.fetchSignalAccount(for: value, tx: tx)
        case .userProfile(let value):
            return userProfileStore.fetchUserProfile(for: value, tx: tx)
        case .signalRecipient(let value):
            return signalRecipientStore.fetchRecipient(rowId: value, tx: tx)
        case .usernameLookupRecord(let value):
            return usernameLookupRecordStore.fetchOne(forAci: value, tx: tx)
        }
    }

    // MARK: - Indexing

    public func insert(_ indexableName: IndexableName, tx: DBWriteTransaction) {
        guard let value = indexableName.indexableNameContent() else {
            return
        }
        let normalizedValue = FullTextSearchIndexer.normalizeText(value)
        do {
            let (identifierColumn, identifierValue) = indexableName.indexableNameIdentifier().columnNameAndValue()
            try dbForWriteTx(tx).execute(
                sql: """
                INSERT INTO "\(Constants.databaseTableName)" ("\(identifierColumn.rawValue)", "value") VALUES (?, ?)
                """,
                arguments: [identifierValue, normalizedValue]
            )
        } catch {
            Logger.warn("Couldn't insert object: \(error.grdbErrorForLogging)")
        }
    }

    public func update(_ indexableName: IndexableName, tx: DBWriteTransaction) {
        delete(indexableName, tx: tx)
        insert(indexableName, tx: tx)
    }

    public func delete(_ indexableName: IndexableName, tx: DBWriteTransaction) {
        do {
            let (identifierColumn, identifierValue) = indexableName.indexableNameIdentifier().columnNameAndValue()
            try dbForWriteTx(tx).execute(
                sql: """
                DELETE FROM "\(Constants.databaseTableName)" WHERE "\(identifierColumn.rawValue)"=?
                """,
                arguments: [identifierValue]
            )
        } catch {
            Logger.warn("Couldn't delete object: \(error.grdbErrorForLogging)")
        }
    }

    public func indexEverything(tx: DBWriteTransaction) {
        TSThread.anyEnumerate(transaction: SDSDB.shimOnlyBridge(tx)) { thread, _ in
            insert(thread, tx: tx)
        }
        SignalAccount.anyEnumerate(transaction: SDSDB.shimOnlyBridge(tx)) { signalAccount, _ in
            insert(signalAccount, tx: tx)
        }
        OWSUserProfile.anyEnumerate(transaction: SDSDB.shimOnlyBridge(tx)) { userProfile, _ in
            insert(userProfile, tx: tx)
        }
        SignalRecipient.anyEnumerate(transaction: SDSDB.shimOnlyBridge(tx)) { signalRecipient, _ in
            insert(signalRecipient, tx: tx)
        }
        usernameLookupRecordStore.enumerateAll(tx: tx) { usernameLookupRecord in
            insert(usernameLookupRecord, tx: tx)
        }
    }
}

// MARK: - IdentifierColumnName

private enum IdentifierColumnName: String {
    case threadId
    case signalAccountId
    case userProfileId
    case signalRecipientId
    case usernameLookupRecordId
}

// MARK: - IndexableNames

public enum IndexableNameIdentifier {
    case tsThread(Int64)
    case signalAccount(Int64)
    case userProfile(Int64)
    case signalRecipient(Int64)
    case usernameLookupRecord(Aci)

    fileprivate func columnNameAndValue() -> (IdentifierColumnName, DatabaseValue) {
        switch self {
        case .tsThread(let value):
            return (.threadId, value.databaseValue)
        case .signalAccount(let value):
            return (.signalAccountId, value.databaseValue)
        case .userProfile(let value):
            return (.userProfileId, value.databaseValue)
        case .signalRecipient(let value):
            return (.signalRecipientId, value.databaseValue)
        case .usernameLookupRecord(let value):
            return (.usernameLookupRecordId, Data(value.serviceIdBinary).databaseValue)
        }
    }
}

public protocol IndexableName {
    func indexableNameIdentifier() -> IndexableNameIdentifier
    func indexableNameContent() -> String?
}

extension TSThread: IndexableName {
    public func indexableNameIdentifier() -> IndexableNameIdentifier {
        return .tsThread(grdbId!.int64Value)
    }

    public func indexableNameContent() -> String? {
        switch self {
        case let groupThread as TSGroupThread:
            return groupThread.groupModel.groupNameOrDefault
        case let storyThread as TSPrivateStoryThread:
            // This will return "My Story" for that thread.
            return storyThread.name
        default:
            return nil
        }
    }
}

extension SignalAccount: IndexableName {
    public func indexableNameIdentifier() -> IndexableNameIdentifier {
        return .signalAccount(grdbId!.int64Value)
    }

    public func indexableNameContent() -> String? {
        guard let nameComponents = contactNameComponents() else {
            return nil
        }

        let systemContactName = DisplayName.SystemContactName(
            nameComponents: nameComponents,
            multipleAccountLabel: nil
        )

        let fullName = systemContactName.resolvedValue(config: DisplayName.Config(shouldUseNicknames: false))
        let nickname = systemContactName.resolvedValue(config: DisplayName.Config(shouldUseNicknames: true))

        return [fullName, nickname]
            .removingDuplicates(uniquingElementsBy: { $0 })
            .joined(separator: " ")
    }
}

extension OWSUserProfile: IndexableName {
    public func indexableNameIdentifier() -> IndexableNameIdentifier {
        return .userProfile(grdbId!.int64Value)
    }

    public func indexableNameContent() -> String? {
        if phoneNumber == Constants.localProfilePhoneNumber {
            // We don't need to index the user profile for the local user.
            return nil
        }
        guard let nameComponents else {
            return nil
        }
        // You can't set a nickname, so this value doesn't matter.
        let config = DisplayName.Config(shouldUseNicknames: false)
        return DisplayName.profileName(nameComponents).resolvedValue(config: config)
    }
}

extension SignalRecipient: IndexableName {
    public func indexableNameIdentifier() -> IndexableNameIdentifier {
        return .signalRecipient(grdbId!.int64Value)
    }

    public func indexableNameContent() -> String? {
        guard let phoneNumber else {
            return nil
        }

        let nationalNumber: String? = { (phoneNumber: String) -> String? in
            guard phoneNumber != OWSUserProfile.Constants.localProfilePhoneNumber else {
                return nil
            }

            guard let phoneNumberObj = SignalServiceKit.PhoneNumber(fromE164: phoneNumber) else {
                owsFailDebug("unexpected unparsable recipientId: \(phoneNumber)")
                return nil
            }

            guard let digitScalars = phoneNumberObj.nationalNumberFormatted?.unicodeScalars.filter({ CharacterSet.decimalDigits.contains($0) }) else {
                owsFailDebug("unexpected unparsable recipientId: \(phoneNumber)")
                return nil
            }

            return String(String.UnicodeScalarView(digitScalars))
        }(phoneNumber.stringValue)

        return [phoneNumber.stringValue, nationalNumber]
            .compacted()
            .removingDuplicates(uniquingElementsBy: { $0 })
            .joined(separator: " ")
    }
}

extension UsernameLookupRecord: IndexableName {
    public func indexableNameIdentifier() -> IndexableNameIdentifier {
        return .usernameLookupRecord(Aci(fromUUID: aci))
    }

    public func indexableNameContent() -> String? {
        return username
    }
}
