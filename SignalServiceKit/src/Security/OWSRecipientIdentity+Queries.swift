//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

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

    @objc(noLongerVerifiedAddressesInGroup:limit:transaction:)
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

    private class func sqlQueryToFetchVerifiedAddresses(groupUniqueID: String,
                                                        withVerificationState state: OWSVerificationState,
                                                        negated: Bool,
                                                        limit: Int) -> String {
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
        let groupMember_uuidString = TSGroupMember.columnName(.serviceId, fullyQualified: true)

        let recipient_id = "\(signalRecipientColumnFullyQualified: .id)"
        let recipient_recipientPhoneNumber = "\(signalRecipientColumnFullyQualified: .phoneNumber)"
        let recipient_recipientUUID = "\(signalRecipientColumnFullyQualified: .aciString)"
        let recipient_uniqueID = "\(signalRecipientColumnFullyQualified: .uniqueId)"

        let recipientIdentity_uniqueID = "\(recipientIdentityColumnFullyQualified: .uniqueId)"
        let exceptClause = "\(recipient_recipientUUID) != ?"
        let sql =
        """
        SELECT \(recipient_recipientUUID), \(recipient_recipientPhoneNumber)
        FROM \(SignalRecipient.databaseTableName),
             \(RecipientIdentityRecord.databaseTableName),
             \(TSGroupMember.databaseTableName)
        WHERE  \(recipient_uniqueID) = \(recipientIdentity_uniqueID) AND
               \(groupMember_groupThreadID) = ? AND
               (\(groupMember_uuidString) = \(recipient_recipientUUID) OR
                \(groupMember_phoneNumber) = \(recipient_recipientPhoneNumber)) AND
               \(exceptClause) AND
               \(stateClause)
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
            let localRecipientUUID = tsAccountManager.localAddress?.uuidString ?? "fake"
            let sql = sqlQueryToFetchVerifiedAddresses(groupUniqueID: groupUniqueID,
                                                       withVerificationState: state,
                                                       negated: negated,
                                                       limit: limit)
            do {
                let args = [groupUniqueID, localRecipientUUID]
                let cursor = try Row.fetchCursor(grdbTransaction.database,
                                                 sql: sql,
                                                 arguments: StatementArguments(args))
                let mapped = cursor.map { row in
                    return SignalServiceAddress(uuid: row[0], phoneNumber: row[1])
                }
                return try Array(mapped)
            } catch {
                owsFailDebug("error: \(error)")
                return []
            }
        }
    }
}
