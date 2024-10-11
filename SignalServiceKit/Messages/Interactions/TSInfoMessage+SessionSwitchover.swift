//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension TSInfoMessage {
    static func makeForSessionSwitchover(
        contactThread: TSContactThread,
        timestamp: UInt64 = MessageTimestampGenerator.sharedInstance.generateTimestamp(),
        phoneNumber: String?
    ) -> TSInfoMessage {
        let infoMessageUserInfo: [InfoMessageUserInfoKey: Any] = if let phoneNumber {
            [.sessionSwitchoverPhoneNumber: phoneNumber]
        } else {
            [:]
        }

        return TSInfoMessage(
            thread: contactThread,
            messageType: .sessionSwitchover,
            timestamp: timestamp,
            infoMessageUserInfo: infoMessageUserInfo
        )
    }
}

public extension TSInfoMessage {
    var sessionSwitchoverPhoneNumber: String? {
        return infoMessageValue(forKey: .sessionSwitchoverPhoneNumber)
    }

    @objc
    func sessionSwitchoverDescription(tx: SDSAnyReadTransaction) -> String {
        if let phoneNumber = sessionSwitchoverPhoneNumber {
            let displayName = contactThreadDisplayName(tx: tx)
            let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(e164: phoneNumber)
            let formatString = OWSLocalizedString(
                "SESSION_SWITCHOVER_EVENT",
                comment: "If you send a message to a phone number, we might not know the owner of the account. When you later learn the owner of the account, we may show this message. The first parameter is a phone number; the second parameter is the contact's name. Put differently, this message indicates that a phone number belongs to a particular named recipient."
            )
            return String(format: formatString, formattedPhoneNumber, displayName)
        } else {
            let address = TSContactThread.contactAddress(fromThreadId: uniqueThreadId, transaction: tx)
            return TSErrorMessage.safetyNumberChangeDescription(for: address, tx: tx)
        }
    }

    private func contactThreadDisplayName(tx: SDSAnyReadTransaction) -> String {
        guard
            let contactThread = DependenciesBridge.shared.threadStore
                .fetchThread(uniqueId: uniqueThreadId, tx: tx.asV2Read) as? TSContactThread
        else {
            return CommonStrings.unknownUser
        }

        return SSKEnvironment.shared.contactManagerRef.displayName(
            for: contactThread.contactAddress,
            tx: tx
        ).resolvedValue()
    }
}
