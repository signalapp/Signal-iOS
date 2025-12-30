//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public final class GroupCallInteractionFinder {
    public init() {}

    /// This method exists exclusively to power a legacy scenario – see its
    /// callers for more info.
    ///
    /// This query is powered by a one-off index:
    /// `index_model_TSInteraction_on_uniqueThreadId_and_eraId_and_recordType`.
    /// Consequently, if we decide in the future that we can drop this query, we
    /// can also drop the index.
    public func existsGroupCallMessageForEraId(
        _ eraId: String,
        thread: TSThread,
        transaction: DBReadTransaction,
    ) -> Bool {
        let sql = """
        SELECT 1
        FROM \(InteractionRecord.databaseTableName)
        \(DEBUG_INDEXED_BY("Interaction_groupCallEraId_partial", or: "index_model_TSInteraction_on_uniqueThreadId_and_eraId_and_recordType"))
        WHERE \(interactionColumn: .recordType) IS \(SDSRecordType.groupCallMessage.rawValue)
        AND \(interactionColumn: .threadUniqueId) = ?
        AND \(interactionColumn: .eraId) = ?
        LIMIT 1
        """

        let arguments: StatementArguments = [thread.uniqueId, eraId]
        return failIfThrows {
            return try Bool.fetchOne(
                transaction.database,
                sql: sql,
                arguments: arguments,
            ) ?? false
        }
    }

    public func unendedCallsForGroupThread(
        _ thread: TSThread,
        transaction: DBReadTransaction,
    ) -> [OWSGroupCallMessage] {
        let sql: String = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        \(DEBUG_INDEXED_BY("Interaction_unendedGroupCall_partial", or: "index_model_TSInteraction_on_uniqueThreadId_and_hasEnded_and_recordType"))
        WHERE \(interactionColumn: .recordType) = \(SDSRecordType.groupCallMessage.rawValue)
        AND \(interactionColumn: .hasEnded) = 0
        AND \(interactionColumn: .threadUniqueId) = ?
        """

        var groupCalls: [OWSGroupCallMessage] = []
        let cursor = OWSGroupCallMessage.grdbFetchCursor(
            sql: sql,
            arguments: [thread.uniqueId],
            transaction: transaction,
        )

        do {
            while let interaction = try cursor.next() {
                guard let groupCall = interaction as? OWSGroupCallMessage, !groupCall.hasEnded else {
                    owsFailDebug("Unexpectedly result: \(interaction.timestamp)")
                    continue
                }
                groupCalls.append(groupCall)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }
        return groupCalls
    }
}
