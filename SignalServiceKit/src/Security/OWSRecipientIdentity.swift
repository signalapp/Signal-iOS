//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public enum VerificationState: Equatable {
    case verified
    case noLongerVerified
    case implicit(isAcknowledged: Bool)

    init(_ verificationState: OWSVerificationState) {
        switch verificationState {
        case .default:
            self = .implicit(isAcknowledged: false)
        case .defaultAcknowledged:
            self = .implicit(isAcknowledged: true)
        case .verified:
            self = .verified
        case .noLongerVerified:
            self = .noLongerVerified
        }
    }

    var rawValue: OWSVerificationState {
        switch self {
        case .implicit(isAcknowledged: false):
            return .default
        case .implicit(isAcknowledged: true):
            return .defaultAcknowledged
        case .verified:
            return .verified
        case .noLongerVerified:
            return .noLongerVerified
        }
    }
}

extension OWSRecipientIdentity {
    public var identityKeyObject: IdentityKey {
        get throws {
            try IdentityKey(publicKey: PublicKey(keyData: identityKey))
        }
    }

    public class func groupContainsUnverifiedMember(
        _ threadUniqueId: String,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        let identityKeys = groupMemberIdentityKeys(
            in: threadUniqueId,
            matching: .verified,
            negated: true,
            limit: 1,
            tx: transaction
        )
        return !identityKeys.isEmpty
    }

    public class func noLongerVerifiedIdentityKeys(
        in threadUniqueId: String,
        tx: SDSAnyReadTransaction
    ) -> [SignalServiceAddress: Data] {
        return groupMemberIdentityKeys(in: threadUniqueId, matching: .noLongerVerified, negated: false, tx: tx)
    }

    private class func sqlQueryToFetchIdentityKeys(
        matching verificationState: OWSVerificationState,
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
        let stateClause = "\(recipientIdentityColumnFullyQualified: .verificationState) \(comparisonOperator) \(verificationState.rawValue)"

        let groupMember_phoneNumber = TSGroupMember.columnName(.phoneNumber, fullyQualified: true)
        let groupMember_groupThreadID = TSGroupMember.columnName(.groupThreadId, fullyQualified: true)
        let groupMember_serviceIdString = TSGroupMember.columnName(.serviceId, fullyQualified: true)

        let recipient_id = "\(signalRecipientColumnFullyQualified: .id)"
        let recipient_phoneNumber = "\(signalRecipientColumnFullyQualified: .phoneNumber)"
        let recipient_aciString = "\(signalRecipientColumnFullyQualified: .aciString)"
        let recipient_pniString = "\(signalRecipientColumnFullyQualified: .pni)"
        let recipient_uniqueID = "\(signalRecipientColumnFullyQualified: .uniqueId)"

        let recipientIdentity_uniqueID = "\(recipientIdentityColumnFullyQualified: .uniqueId)"
        let recipientIdentity_identityKey = "\(recipientIdentityColumnFullyQualified: .identityKey)"
        let exceptClause = "\(recipient_aciString) != ?"
        let sql =
        """
            SELECT \(recipient_aciString), \(recipient_phoneNumber), \(recipient_pniString), \(recipientIdentity_identityKey)
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

    private class func groupMemberIdentityKeys(
        in threadUniqueId: String,
        matching verificationState: OWSVerificationState,
        negated: Bool,
        limit: Int = Int.max,
        tx: SDSAnyReadTransaction
    ) -> [SignalServiceAddress: Data] {
        switch tx.readTransaction {
        case .grdbRead(let grdbTransaction):
            // There should always be a recipient UUID, but just in case there isn't provide a fake value that won't
            // affect the results of the query.
            let localRecipientAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci
            let sql = sqlQueryToFetchIdentityKeys(matching: verificationState, negated: negated, limit: limit)
            do {
                let args = [threadUniqueId, localRecipientAci?.serviceIdUppercaseString ?? "fake"]
                let cursor = try Row.fetchCursor(grdbTransaction.database, sql: sql, arguments: StatementArguments(args))
                var result = [SignalServiceAddress: Data]()
                while let row = try cursor.next() {
                    result[SignalServiceAddress(serviceIdString: row[0] ?? row[2], phoneNumber: row[1])] = row[3]
                }
                return result
            } catch {
                owsFailDebug("error: \(error)")
                return [:]
            }
        }
    }
}
