//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
public import LibSignalClient

private extension OWSVerificationState {
    var protoState: SSKProtoVerifiedState {
        switch self {
        case .default, .defaultAcknowledged:
            return .default
        case .verified:
            return .verified
        case .noLongerVerified:
            return .unverified
        }
    }
}

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

/// Record for a recipient's identity key and associated fields used to make trust decisions.
public final class OWSRecipientIdentity: NSObject, SDSCodableModel, Decodable {
    public static let databaseTableName = "model_OWSRecipientIdentity"
    public static var recordType: UInt { SDSRecordType.recipientIdentity.rawValue }

    public var id: Int64?
    public let uniqueId: String
    public let identityKey: Data
    public let createdAt: Date
    public let isFirstKnownKey: Bool

    public internal(set) var verificationState: OWSVerificationState

    public init(
        uniqueId: String,
        identityKey: Data,
        isFirstKnownKey: Bool,
        createdAt: Date,
        verificationState: OWSVerificationState,
    ) {
        self.uniqueId = uniqueId
        self.identityKey = identityKey
        self.isFirstKnownKey = isFirstKnownKey
        self.createdAt = createdAt
        self.verificationState = verificationState
    }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case accountId
        case identityKey
        case createdAt
        case isFirstKnownKey
        case verificationState
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(UInt.self, forKey: .recordType)
        guard decodedRecordType == Self.recordType else {
            owsFailDebug("Unexpected record type: \(decodedRecordType)")
            throw SDSError.invalidValue()
        }

        self.id = try container.decode(Int64.self, forKey: .id)
        self.uniqueId = try container.decode(String.self, forKey: .uniqueId)
        self.identityKey = try container.decode(Data.self, forKey: .identityKey)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.isFirstKnownKey = try container.decode(Bool.self, forKey: .isFirstKnownKey)
        self.verificationState = OWSVerificationState(rawValue: UInt64(bitPattern: try container.decode(Int64.self, forKey: .verificationState))) ?? .noLongerVerified
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.id, forKey: .id)
        try container.encode(Self.recordType, forKey: .recordType)
        try container.encode(self.uniqueId, forKey: .uniqueId)
        try container.encode(self.uniqueId, forKey: .accountId)
        try container.encode(self.identityKey, forKey: .identityKey)
        try container.encode(self.createdAt, forKey: .createdAt)
        try container.encode(self.isFirstKnownKey, forKey: .isFirstKnownKey)
        try container.encode(Int64(bitPattern: self.verificationState.rawValue), forKey: .verificationState)
    }

    public var wasIdentityVerified: Bool {
        switch self.verificationState {
        case .verified, .noLongerVerified:
            return true
        case .default, .defaultAcknowledged:
            return false
        }
    }

    public var identityKeyObject: IdentityKey {
        get throws {
            try IdentityKey(publicKey: PublicKey(keyData: identityKey))
        }
    }

    public class func groupContainsUnverifiedMember(
        _ threadUniqueId: String,
        transaction: DBReadTransaction,
    ) -> Bool {
        let identityKeys = groupMemberIdentityKeys(
            in: threadUniqueId,
            matching: .verified,
            negated: true,
            limit: 1,
            tx: transaction,
        )
        return !identityKeys.isEmpty
    }

    public class func noLongerVerifiedIdentityKeys(
        in threadUniqueId: String,
        tx: DBReadTransaction,
    ) -> [SignalServiceAddress: Data] {
        return groupMemberIdentityKeys(in: threadUniqueId, matching: .noLongerVerified, negated: false, tx: tx)
    }

    private class func sqlQueryToFetchIdentityKeys(
        matching verificationState: OWSVerificationState,
        negated: Bool,
        limit: Int,
    ) -> String {
        let limitClause: String
        if limit < Int.max {
            limitClause = "LIMIT \(limit)"
        } else {
            limitClause = ""
        }

        let comparisonOperator = negated ? "!=" : "="
        let recipientIdentity_verificationState = OWSRecipientIdentity.columnName(.verificationState, fullyQualified: true)
        let stateClause = "\(recipientIdentity_verificationState) \(comparisonOperator) \(verificationState.rawValue)"

        let groupMember_phoneNumber = TSGroupMember.columnName(.phoneNumber, fullyQualified: true)
        let groupMember_groupThreadID = TSGroupMember.columnName(.groupThreadId, fullyQualified: true)
        let groupMember_serviceIdString = TSGroupMember.columnName(.serviceId, fullyQualified: true)

        let recipient_id = "\(signalRecipientColumnFullyQualified: .id)"
        let recipient_phoneNumber = "\(signalRecipientColumnFullyQualified: .phoneNumber)"
        let recipient_aciString = "\(signalRecipientColumnFullyQualified: .aciString)"
        let recipient_pniString = "\(signalRecipientColumnFullyQualified: .pni)"
        let recipient_uniqueID = "\(signalRecipientColumnFullyQualified: .uniqueId)"

        let recipientIdentity_uniqueID = OWSRecipientIdentity.columnName(.uniqueId, fullyQualified: true)
        let recipientIdentity_identityKey = OWSRecipientIdentity.columnName(.identityKey, fullyQualified: true)
        let exceptClause = "\(recipient_aciString) != ?"
        let sql =
            """
                SELECT \(recipient_aciString), \(recipient_phoneNumber), \(recipient_pniString), \(recipientIdentity_identityKey)
                FROM
                    \(SignalRecipient.databaseTableName),
                    \(OWSRecipientIdentity.databaseTableName),
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
        tx: DBReadTransaction,
    ) -> [SignalServiceAddress: Data] {
        // There should always be a recipient UUID, but just in case there isn't provide a fake value that won't
        // affect the results of the query.
        let localRecipientAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci
        let sql = sqlQueryToFetchIdentityKeys(matching: verificationState, negated: negated, limit: limit)
        do {
            let args = [threadUniqueId, localRecipientAci?.serviceIdUppercaseString ?? "fake"]
            let cursor = try Row.fetchCursor(tx.database, sql: sql, arguments: StatementArguments(args))
            var result = [SignalServiceAddress: Data]()
            while let row = try cursor.next() {
                let normalizedAddress = NormalizedDatabaseRecordAddress(
                    aci: (row[0] as String?).flatMap { try? Aci.parseFrom(serviceIdString: $0) },
                    phoneNumber: row[1],
                    pni: (row[2] as String?).flatMap { try? Pni.parseFrom(serviceIdString: $0) },
                )
                let address = SignalServiceAddress(
                    serviceId: normalizedAddress?.serviceId,
                    phoneNumber: normalizedAddress?.phoneNumber,
                )
                result[address] = row[3]
            }
            return result
        } catch {
            owsFailDebug("error: \(error)")
            return [:]
        }
    }

    @objc
    public class func buildVerifiedProto(
        destinationAci: AciObjC,
        identityKey: Data,
        verificationState: OWSVerificationState,
        paddingBytesLength: UInt,
    ) -> SSKProtoVerified {
        owsAssertDebug(identityKey.count == OWSIdentityManagerImpl.Constants.identityKeyLength)
        // We only sync users marking as verified. Never sync the conflicted state;
        // the sibling device will figure that out on its own.
        owsAssertDebug(verificationState != .noLongerVerified)

        let verifiedBuilder = SSKProtoVerified.builder()
        if BuildFlags.serviceIdStrings {
            verifiedBuilder.setDestinationAci(destinationAci.wrappedAciValue.serviceIdString)
        }
        if BuildFlags.serviceIdBinaryConstantOverhead {
            verifiedBuilder.setDestinationAciBinary(destinationAci.wrappedAciValue.serviceIdBinary)
        }
        verifiedBuilder.setIdentityKey(identityKey)
        verifiedBuilder.setState(verificationState.protoState)
        if paddingBytesLength > 0 {
            // We add the same amount of padding in the VerificationStateSync message
            // and its corresponding NullMessage so that the sync message is
            // indistinguishable from an outgoing Sent transcript corresponding to the
            // NullMessage. We pad the NullMessage so as to obscure its content. The
            // sync message (like all sync messages) will be *additionally* padded by
            // the superclass while being sent. The end result is we send a NullMessage
            // of a non-distinct size, and a verification sync which is ~1-512 bytes
            // larger than that.
            verifiedBuilder.setNullMessage(Randomness.generateRandomBytes(paddingBytesLength))
        }
        return verifiedBuilder.buildInfallibly()
    }
}
