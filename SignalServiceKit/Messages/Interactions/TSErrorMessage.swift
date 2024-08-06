//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

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
        let recipientDisplayName = contactsManager.displayName(for: address, tx: tx).resolvedValue()
        return String(format: messageFormat, recipientDisplayName)
    }
}
