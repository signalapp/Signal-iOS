//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class BackupReceiptCredentialRedemptionJobRecord: JobRecord, FactoryInitializableFromRecordType {
    /// Represents the state of an in-progress attempt to redeem a subscription.
    ///
    /// It's important that we update this over the duration of the job, because
    /// (generally) once we've made a receipt-credential-related request to the
    /// server remote state has been set. If the app exits between making two
    /// requests, we need to have stored the data we sent in the first request
    /// so we can retry the second.
    ///
    /// Much like for donations, there are two network requests required to
    /// redeem a receipt credential for a Backups subscription.
    ///
    /// The first is to "request a receipt credential", which takes a
    /// locally-generated "receipt credential request" and returns us data we
    /// can use to construct a "receipt credential presentation". Once we have
    /// the receipt credential presentation, we can discard the receipt
    /// credential request.
    ///
    /// The second is to "redeem the receipt credential", which sends the
    /// receipt credential presentation from the first request to the service,
    /// which validates it and subsequently records that our account is now
    /// eligible (or has extended its eligibility) for paid-tier Backups. When
    /// this completes, the attempt is complete.
    enum RedemptionAttemptState {
        /// This attempt is at a clean slate.
        case unattempted

        /// We need to request a receipt credential, using the associated
        /// request and context objects.
        ///
        /// Note that it is safe to request a receipt credential multiple times,
        /// as long as the request/context are the same across retries. Receipt
        /// credential requests do not expire, and the returned receipt
        /// credential will always correspond to the latest entitling
        /// transaction.
        case receiptCredentialRequesting(
            request: ReceiptCredentialRequest,
            context: ReceiptCredentialRequestContext
        )

        /// We have a receipt credential, and need to redeem it.
        ///
        /// Note that it is safe to attempt to redeem a receipt credential
        /// multiple times for the same subscription period.
        case receiptCredentialRedemption(ReceiptCredential)
    }

    override class var jobRecordType: JobRecordType { .backupReceiptsCredentialRedemption }

    let subscriberId: Data
    private(set) var attemptState: RedemptionAttemptState

    init(subscriberId: Data) {
        self.subscriberId = subscriberId
        self.attemptState = .unattempted

        super.init(failureCount: 0, status: .ready)
    }

    func updateAttemptState(
        _ newAttemptState: RedemptionAttemptState,
        tx: DBWriteTransaction
    ) {
        attemptState = newAttemptState
        anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func delete(tx: DBWriteTransaction) {
        anyRemove(transaction: SDSDB.shimOnlyBridge(tx))
    }

    // MARK: -

    init(forRecordTypeFactoryInitializationFrom decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let persistedState = try container.decode(PersistedState.self, forKey: .BRCRJR_state)
        self.subscriberId = persistedState.subscriberId
        self.attemptState = persistedState.attemptState

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        let persistedState = PersistedState(
            subscriberId: subscriberId,
            attemptState: attemptState
        )
        try container.encode(persistedState, forKey: .BRCRJR_state)

        try super.encode(to: container.superEncoder())
    }
}

// MARK: -

extension BackupReceiptCredentialRedemptionJobRecord {
    private struct PersistedState: Codable {
        typealias RedemptionAttemptState = BackupReceiptCredentialRedemptionJobRecord.RedemptionAttemptState

        let subscriberId: Data
        let attemptState: RedemptionAttemptState

        init(subscriberId: Data, attemptState: RedemptionAttemptState) {
            self.subscriberId = subscriberId
            self.attemptState = attemptState
        }

        // MARK: Codable

        private enum CodingKeys: String, CodingKey {
            case subscriberId
            case receiptCredentialRequest
            case receiptCredentialRequestContext
            case receiptCredential
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.subscriberId = try container.decode(Data.self, forKey: .subscriberId)

            if
                let requestData = try container.decodeIfPresent(Data.self, forKey: .receiptCredentialRequest),
                let contextData = try container.decodeIfPresent(Data.self, forKey: .receiptCredentialRequestContext)
            {
                attemptState = .receiptCredentialRequesting(
                    request: try ReceiptCredentialRequest(contents: [UInt8](requestData)),
                    context: try ReceiptCredentialRequestContext(contents: [UInt8](contextData))
                )
            } else if
                let credentialData = try container.decodeIfPresent(Data.self, forKey: .receiptCredential)
            {
                attemptState = .receiptCredentialRedemption(
                    try ReceiptCredential(contents: [UInt8](credentialData))
                )
            } else {
                attemptState = .unattempted
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(subscriberId, forKey: .subscriberId)

            switch attemptState {
            case .receiptCredentialRequesting(let request, let context):
                try container.encode(request.serialize().asData, forKey: .receiptCredentialRequest)
                try container.encode(context.serialize().asData, forKey: .receiptCredentialRequestContext)
            case .receiptCredentialRedemption(let credential):
                try container.encode(credential.serialize().asData, forKey: .receiptCredential)
            case .unattempted:
                break
            }
        }
    }
}
