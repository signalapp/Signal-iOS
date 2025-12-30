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

public struct EditMessageStore {

    public init() {}

    // MARK: - Reads

    public func editTarget(
        timestamp: UInt64,
        authorAci: Aci?,
        tx: DBReadTransaction,
    ) -> EditMessageTarget? {
        guard SDS.fitsInInt64(timestamp) else {
            owsFailDebug("Received invalid timestamp!")
            return nil
        }
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        \(DEBUG_INDEXED_BY("Interaction_timestamp", or: "index_interactions_on_timestamp_sourceDeviceId_and_authorPhoneNumber"))
        WHERE \(interactionColumn: .timestamp) = ?
        AND \(interactionColumn: .authorUUID) IS ?
        LIMIT 1
        """
        let interaction = TSInteraction.grdbFetchOne(
            sql: sql,
            arguments: [timestamp, authorAci?.serviceIdUppercaseString],
            transaction: tx,
        )
        switch (interaction, authorAci) {
        case (let outgoingMessage as TSOutgoingMessage, nil):
            guard let thread = outgoingMessage.thread(tx: tx) else {
                Logger.warn("No thread for message")
                return nil
            }
            return .outgoingMessage(OutgoingEditMessageWrapper(
                message: outgoingMessage,
                thread: thread,
            ))
        case (let incomingMessage as TSIncomingMessage, let authorAci?):
            guard let thread = incomingMessage.thread(tx: tx) else {
                Logger.warn("No thread for message")
                return nil
            }
            return .incomingMessage(IncomingEditMessageWrapper(
                message: incomingMessage,
                thread: thread,
                authorAci: authorAci,
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
        tx: DBReadTransaction,
    ) -> TSMessage? {
        let transaction = tx

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
            transaction: transaction,
        ) as? TSMessage
    }

    public func numberOfEdits(
        for message: TSMessage,
        tx: DBReadTransaction,
    ) -> Int {
        let sql = """
            SELECT COUNT(*)
            FROM \(EditRecord.databaseTableName)
            WHERE editRecord.latestRevisionId = ?
        """

        let arguments: StatementArguments = [message.grdbId]

        return failIfThrows {
            return try Int.fetchOne(
                tx.database,
                sql: sql,
                arguments: arguments,
            ) ?? 0
        }
    }

    /// Fetches all past revisions for the given most-recent-revision message.
    ///
    /// - Returns
    /// An edit record and message instance (if one is found) for each past
    /// revision, from newest to oldest.
    public func findEditHistory<MessageType: TSMessage>(
        forMostRecentRevision message: MessageType,
        tx: DBReadTransaction,
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
            tx.database,
            sql: recordSQL,
            arguments: arguments,
        )

        return records.map { record -> (EditRecord, MessageType?) in
            let interaction = InteractionFinder.fetch(
                rowId: record.pastRevisionId,
                transaction: tx,
            )
            guard let message = interaction as? MessageType else {
                owsFailDebug("Interaction has unexpected type: \(type(of: interaction))")
                return (record, nil)
            }
            return (record: record, edit: message)
        }
    }

    /// Fetches all EditRecords related to `message`.
    ///
    /// The `message` may be the latest revision or a past revision.
    ///
    /// The EditRecords are fetched "recursively", meaning that every EditRecord
    /// that references a message ID which is referenced by any element of the
    /// result will be returned. This is useful when deleting messages because
    /// it allows us to maintain invariants required by FOREIGN KEY constraints.
    ///
    /// For example, if the revision "graph" is well-formed, we'll return
    /// EditRecords with distinct pastRevisionIds (e.g., 102, 103) which all
    /// refer to the same latestRevisionId (e.g., 101), and we'll return this
    /// exact same result regardless of whether `message` refers to a past
    /// revision (e.g., 102) or the latest revision (e.g., 101).
    ///
    /// If the revision "graph" isn't well-formed, we must fetch extra
    /// EditRecords to ensure we delete all the EditRecords that reference the
    /// messages that are about to be deleted.
    public func findEditRecords(
        relatedTo message: TSMessage,
        tx: DBReadTransaction,
    ) throws -> [EditRecord] {
        // We need to fetch every EditRecord that references message.grdbId or
        // anything that those EditRecords reference, recursively.

        var revisionIdsToCheck = [message.sqliteRowId].compacted()
        var alreadyCheckedRevisionIds = Set<Int64>()

        var editRecords = [EditRecord]()
        while !revisionIdsToCheck.isEmpty {
            let revisionId = revisionIdsToCheck.removeFirst()
            guard alreadyCheckedRevisionIds.insert(revisionId).inserted else {
                continue
            }
            let records = try EditRecord.filter(
                Column(EditRecord.CodingKeys.latestRevisionId) == revisionId
                    || Column(EditRecord.CodingKeys.pastRevisionId) == revisionId,
            ).fetchAll(tx.database)
            revisionIdsToCheck.append(contentsOf: records.map(\.latestRevisionId))
            revisionIdsToCheck.append(contentsOf: records.map(\.pastRevisionId))
            editRecords.append(contentsOf: records)
        }

        // We'll have duplicates because some will be fetched repeatedly.
        return editRecords.removingDuplicates(uniquingElementsBy: { $0.id! })
    }

    // MARK: - Writes

    public func insert(
        _ editRecord: EditRecord,
        tx: DBWriteTransaction,
    ) throws {
        try editRecord.insert(tx.database)
    }

    public func update(
        _ editRecord: EditRecord,
        tx: DBWriteTransaction,
    ) throws {
        try editRecord.update(tx.database)
    }
}
