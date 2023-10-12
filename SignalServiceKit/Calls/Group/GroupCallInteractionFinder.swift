//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
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
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        let sql = """
        SELECT EXISTS(
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .recordType) IS \(SDSRecordType.groupCallMessage.rawValue)
            AND \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .eraId) = ?
            LIMIT 1
        )
        """

        let arguments: StatementArguments = [thread.uniqueId, eraId]
        do {
            return try Bool.fetchOne(
                transaction.unwrapGrdbRead.database,
                sql: sql,
                arguments: arguments
            ) ?? false
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find group call")
        }
    }

    public func unendedCallsForGroupThread(
        _ thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) -> [OWSGroupCallMessage] {
        let sql: String = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .recordType) IS \(SDSRecordType.groupCallMessage.rawValue)
            AND \(interactionColumn: .hasEnded) IS FALSE
            AND \(interactionColumn: .threadUniqueId) = ?
        """

        var groupCalls: [OWSGroupCallMessage] = []
        let cursor = OWSGroupCallMessage.grdbFetchCursor(
            sql: sql,
            arguments: [thread.uniqueId],
            transaction: transaction.unwrapGrdbRead
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
