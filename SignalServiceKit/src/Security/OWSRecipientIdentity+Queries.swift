//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

extension OWSRecipientIdentity {
    public class func groupContainsUnverifiedMember(
        _ groupUniqueID: String,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        let members = groupMembers(ofGroupWithUniqueID: groupUniqueID,
                                   withVerificationState: .verified,
                                   negated: true,
                                   limit: 1,
                                   transaction: transaction)
        return !members.isEmpty
    }

    public class func noLongerVerifiedAddresses(
        inGroup groupThreadID: String,
        limit: Int,
        transaction: SDSAnyReadTransaction
    ) -> [SignalServiceAddress] {
        return groupMembers(ofGroupWithUniqueID: groupThreadID,
                            withVerificationState: .noLongerVerified,
                            negated: false,
                            limit: limit,
                            transaction: transaction)
    }

    private class func sqlQueryToFetchVerifiedAddresses(
        groupUniqueID: String,
        withVerificationState state: OWSVerificationState,
        negated: Bool,
        limit: Int
    ) -> String {
        let limitClause: String
        if limit < Int.max {
            limitClause = "LIMIT \(limit)"
        } else {
            limitClause = ""
        }
        let comparisonOperator = negated ? "!=" : "="
        let stateClause = "\(recipientIdentityColumnFullyQualified: .verificationState) \(comparisonOperator) \(state.rawValue)"

        let groupMember_phoneNumber = TSGroupMember.columnName(.phoneNumber, fullyQualified: true)
        let groupMember_groupThreadID = TSGroupMember.columnName(.groupThreadId, fullyQualified: true)
        let groupMember_serviceIdString = TSGroupMember.columnName(.serviceId, fullyQualified: true)

        let recipient_id = "\(signalRecipientColumnFullyQualified: .id)"
        let recipient_phoneNumber = "\(signalRecipientColumnFullyQualified: .phoneNumber)"
        let recipient_aciString = "\(signalRecipientColumnFullyQualified: .aciString)"
        let recipient_pniString = "\(signalRecipientColumnFullyQualified: .pni)"
        let recipient_uniqueID = "\(signalRecipientColumnFullyQualified: .uniqueId)"

        let recipientIdentity_uniqueID = "\(recipientIdentityColumnFullyQualified: .uniqueId)"
        let exceptClause = "\(recipient_aciString) != ?"
        let sql =
        """
            SELECT \(recipient_aciString), \(recipient_phoneNumber), \(recipient_pniString)
            FROM
                \(SignalRecipient.databaseTableName),
                \(RecipientIdentityRecord.databaseTableName),
                \(TSGroupMember.databaseTableName)
            WHERE
                \(recipient_uniqueID) = \(recipientIdentity_uniqueID)
                AND \(groupMember_groupThreadID) = ?
                AND (
                    \(groupMember_serviceIdString) = \(recipient_aciString)
                    OR \(groupMember_serviceIdString) = \(recipient_pniString)
                    OR \(groupMember_phoneNumber) = \(recipient_phoneNumber)
                )
                AND \(exceptClause)
                AND \(stateClause)
            ORDER BY \(recipient_id)
            \(limitClause)
        """
        return sql
    }

    private class func groupMembers(
        ofGroupWithUniqueID groupUniqueID: String,
        withVerificationState state: OWSVerificationState,
        negated: Bool,
        limit: Int,
        transaction: SDSAnyReadTransaction
    ) -> [SignalServiceAddress] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            // There should always be a recipient UUID, but just in case there isn't provide a fake value that won't
            // affect the results of the query.
            let localRecipientAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aci
            let sql = sqlQueryToFetchVerifiedAddresses(
                groupUniqueID: groupUniqueID,
                withVerificationState: state,
                negated: negated,
                limit: limit
            )
            do {
                let args = [groupUniqueID, localRecipientAci?.serviceIdUppercaseString ?? "fake"]
                let cursor = try Row.fetchCursor(grdbTransaction.database, sql: sql, arguments: StatementArguments(args))
                let mapped = cursor.map { row in
                    return SignalServiceAddress(serviceIdString: row[0] ?? row[2], phoneNumber: row[1])
                }
                return try Array(mapped)
            } catch {
                owsFailDebug("error: \(error)")
                return []
            }
        }
    }
}
