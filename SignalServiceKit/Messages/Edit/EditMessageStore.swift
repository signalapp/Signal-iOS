//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

public enum EditMessageTarget {
    case outgoingMessage(OutgoingEditMessageWrapper)
    case incomingMessage(IncomingEditMessageWrapper)

    var wrapper: any EditMessageWrapper {
        switch self {
        case .outgoingMessage(let outgoingMessage):
            return outgoingMessage
        case .incomingMessage(let incomingMessage):
            return incomingMessage
        }
    }
}

public protocol EditMessageStore {

    // MARK: - Reads

    func editTarget(
        timestamp: UInt64,
        authorAci: Aci?,
        tx: DBReadTransaction
    ) -> EditMessageTarget?

    func findMessage(
        fromEdit edit: TSMessage,
        tx: DBReadTransaction
    ) -> TSMessage?

    func numberOfEdits(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> Int

    /// Fetches all past revisions for the given most-recent-revision message.
    ///
    /// - Returns
    /// An edit record and message instance (if one is found) for each past
    /// revision, from newest to oldest.
    func findEditHistory<MessageType: TSMessage>(
        for message: MessageType,
        tx: DBReadTransaction
    ) throws -> [(record: EditRecord, message: MessageType?)]

    /// This method is similar to findEditHistory, but will find records and interactions where the
    /// passed in message is _either_ the latest edit, or a past revision.  This is useful when
    /// deleting a message, since the record needs to be removed regardles of the type of edit
    func findEditDeleteRecords<MessageType: TSMessage>(
        for message: MessageType,
        tx: DBReadTransaction
    ) throws -> [(record: EditRecord, message: MessageType?)]

    // MARK: - Writes

    func insert(
        _ editRecord: EditRecord,
        tx: DBWriteTransaction
    ) throws

    func update(
        _ editRecord: EditRecord,
        tx: DBWriteTransaction
    ) throws
}

public class EditMessageStoreImpl: EditMessageStore {

    public init() {}

    public func editTarget(
        timestamp: UInt64,
        authorAci: Aci?,
        tx: DBReadTransaction
    ) -> EditMessageTarget? {
        guard SDS.fitsInInt64(timestamp) else {
            owsFailDebug("Received invalid timestamp!")
            return nil
        }

        let transaction = SDSDB.shimOnlyBridge(tx)

        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .timestamp) = ?
            AND \(interactionColumn: .authorUUID) IS ?
            LIMIT 1
        """
        let interaction = TSInteraction.grdbFetchOne(
            sql: sql,
            arguments: [timestamp, authorAci?.serviceIdUppercaseString],
            transaction: transaction.unwrapGrdbRead
        )
        switch (interaction, authorAci) {
        case (let outgoingMessage as TSOutgoingMessage, nil):
            guard let thread = outgoingMessage.thread(tx: transaction) else {
                Logger.warn("No thread for message")
                return nil
            }
            return .outgoingMessage(OutgoingEditMessageWrapper(
                message: outgoingMessage,
                thread: thread
            ))
        case (let incomingMessage as TSIncomingMessage, let authorAci?):
            guard let thread = incomingMessage.thread(tx: transaction) else {
                Logger.warn("No thread for message")
                return nil
            }
            return .incomingMessage(IncomingEditMessageWrapper(
                message: incomingMessage,
                thread: thread,
                authorAci: authorAci
            ))
        case (.some, _):
            Logger.warn("Unexpected message type found for edit")
            fallthrough
        default:
            return nil
        }
    }

    public func findMessage(
        fromEdit edit: TSMessage,
        tx: DBReadTransaction
    ) -> TSMessage? {
        let transaction = SDSDB.shimOnlyBridge(tx)

        let sql = """
                SELECT * FROM \(InteractionRecord.databaseTableName) AS interaction
                INNER JOIN \(EditRecord.databaseTableName) AS editRecord
                ON interaction.\(interactionColumn: .id) = editRecord.latestRevisionId
                WHERE editRecord.pastRevisionId = ?
                LIMIT 1
            """

        let arguments: StatementArguments = [edit.grdbId]
        return TSMessage.grdbFetchOne(
            sql: sql,
            arguments: arguments,
            transaction: transaction.unwrapGrdbRead
        ) as? TSMessage
    }

    public func numberOfEdits(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> Int {
        let sql = """
                SELECT COUNT(*)
                FROM \(EditRecord.databaseTableName)
                WHERE editRecord.latestRevisionId = ?
            """

        let arguments: StatementArguments = [message.grdbId]

        do {
            return try Int.fetchOne(
                tx.databaseConnection,
                sql: sql,
                arguments: arguments
            ) ?? 0
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Missing instance.")
        }
    }

    public func findEditHistory<MessageType: TSMessage>(
        for message: MessageType,
        tx: DBReadTransaction
    ) throws -> [(record: EditRecord, message: MessageType?)] {
        /// By ordering DESC on `pastRevisionId`, we end up ordering edits
        /// newest-to-oldest. That's because the highest `pastRevisionId` refers
        /// to the most-recently-inserted revision, or newest edit.
        let recordSQL = """
            SELECT * FROM \(EditRecord.databaseTableName)
            WHERE latestRevisionId = ?
            ORDER BY pastRevisionId DESC
        """

        let arguments: StatementArguments = [message.grdbId]

        let records = try EditRecord.fetchAll(
            tx.databaseConnection,
            sql: recordSQL,
            arguments: arguments
        )

        return records.map { record -> (EditRecord, MessageType?) in
            let interaction = InteractionFinder.fetch(
                rowId: record.pastRevisionId,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
            guard let message = interaction as? MessageType else {
                owsFailDebug("Interaction has unexpected type: \(type(of: interaction))")
                return (record, nil)
            }
            return (record: record, edit: message)
        }
    }

    /// This method is similar to findEditHistory, but will find records and interactions where the
    /// passed in message is _either_ the latest edit, or a past revision.  This is useful when
    /// deleting a message, since the record needs to be removed regardles of the type of edit
    public func findEditDeleteRecords<MessageType: TSMessage>(
        for message: MessageType,
        tx: DBReadTransaction
    ) throws -> [(record: EditRecord, message: MessageType?)] {
        let recordSQL = """
            SELECT * FROM \(EditRecord.databaseTableName)
            WHERE latestRevisionId = ?
            OR pastRevisionId = ?
            ORDER BY pastRevisionId DESC
        """

        let arguments: StatementArguments = [message.grdbId, message.grdbId]

        let records = try EditRecord.fetchAll(
            tx.databaseConnection,
            sql: recordSQL,
            arguments: arguments
        )

        return records.map { record -> (EditRecord, MessageType?) in
            let interaction = InteractionFinder.fetch(
                rowId: record.pastRevisionId,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
            guard let message = interaction as? MessageType else {
                owsFailDebug("Interaction has unexpected type: \(type(of: interaction))")
                return (record, nil)
            }
            return (record: record, edit: message)
        }
    }

    public func insert(
        _ editRecord: EditRecord,
        tx: DBWriteTransaction
    ) throws {
        try editRecord.insert(tx.databaseConnection)
    }

    public func update(
        _ editRecord: EditRecord,
        tx: DBWriteTransaction
    ) throws {
        try editRecord.update(tx.databaseConnection)
    }
}
