//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension TSErrorMessage {
    static func sessionRefresh(
        thread: TSThread,
        timestamp: UInt64? = nil
    ) -> TSErrorMessage {
        let builder = TSErrorMessageBuilder(thread: thread, errorType: .sessionRefresh)
        timestamp.map { builder.timestamp = $0 }
        return TSErrorMessage(errorMessageWithBuilder: builder)
    }

    static func nonblockingIdentityChange(
        thread: TSThread,
        timestamp: UInt64? = nil,
        address: SignalServiceAddress,
        wasIdentityVerified: Bool
    ) -> TSErrorMessage {
        let builder = TSErrorMessageBuilder(thread: thread, errorType: .nonBlockingIdentityChange)
        timestamp.map { builder.timestamp = $0 }
        builder.recipientAddress = address
        builder.wasIdentityVerified = wasIdentityVerified
        return TSErrorMessage(errorMessageWithBuilder: builder)
    }

    static func failedDecryption(
        thread: TSThread,
        timestamp: UInt64,
        sender: SignalServiceAddress?
    ) -> TSErrorMessage {
        let builder = TSErrorMessageBuilder(thread: thread, errorType: .decryptionFailure)
        builder.timestamp = timestamp
        builder.senderAddress = sender
        return TSErrorMessage(errorMessageWithBuilder: builder)
    }

    static func failedDecryption(
        sender: SignalServiceAddress,
        groupId: Data?,
        timestamp: UInt64,
        tx: SDSAnyReadTransaction
    ) -> TSErrorMessage? {
        if
            let groupId,
            let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: tx),
            groupThread.groupMembership.isFullMember(sender)
        {
            return .failedDecryption(
                thread: groupThread,
                timestamp: timestamp,
                sender: sender
            )
        } else if let contactThread = TSContactThread.getWithContactAddress(
            sender,
            transaction: tx
        ) {
            return .failedDecryption(
                thread: contactThread,
                timestamp: timestamp,
                sender: sender
            )
        }

        return nil
    }
}

// MARK: -

extension TSErrorMessage {

    public func plaintextBody(_ tx: SDSAnyReadTransaction) -> String {
        return self.rawBody(transaction: tx) ?? ""
    }

    @objc
    static func safetyNumberChangeDescription(for address: SignalServiceAddress?, tx: SDSAnyReadTransaction) -> String {
        guard let address else {
            // address will be nil for legacy errors
            return OWSLocalizedString(
                "ERROR_MESSAGE_NON_BLOCKING_IDENTITY_CHANGE",
                comment: "Shown when signal users safety numbers changed"
            )
        }
        let messageFormat = OWSLocalizedString(
            "ERROR_MESSAGE_NON_BLOCKING_IDENTITY_CHANGE_FORMAT",
            comment: "Shown when signal users safety numbers changed, embeds the user's {{name or phone number}}"
        )
        let recipientDisplayName = SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue()
        return String(format: messageFormat, recipientDisplayName)
    }
}
