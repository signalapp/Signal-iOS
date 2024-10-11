//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension TSInfoMessage {
    static func makeForThreadMerge(
        mergedThread: TSContactThread,
        timestamp: UInt64 = MessageTimestampGenerator.sharedInstance.generateTimestamp(),
        previousE164: String?
    ) -> TSInfoMessage {
        let infoMessageUserInfo: [InfoMessageUserInfoKey: Any] = if let previousE164 {
            [.threadMergePhoneNumber: previousE164]
        } else {
            [:]
        }

        return TSInfoMessage(
            thread: mergedThread,
            messageType: .threadMerge,
            timestamp: timestamp,
            infoMessageUserInfo: infoMessageUserInfo
        )
    }
}

public extension TSInfoMessage {
    /// If this info message represents an E164/PNI -> ACI thread merge event,
    /// returns the "before" thread's E164.
    var threadMergePhoneNumber: String? {
        return infoMessageValue(forKey: .threadMergePhoneNumber)
    }

    @objc
    func threadMergeDescription(tx: SDSAnyReadTransaction) -> String {
        let displayName = contactThreadDisplayName(tx: tx)
        if let phoneNumber = threadMergePhoneNumber {
            let formatString = OWSLocalizedString(
                "THREAD_MERGE_PHONE_NUMBER",
                comment: "A system event shown in a conversation when multiple conversations for the same person have been merged into one. The parameters are replaced with the contact's name (eg John Doe) and their phone number (eg +1 650 555 0100)."
            )
            let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(e164: phoneNumber)
            return String(format: formatString, displayName, formattedPhoneNumber)
        } else {
            let formatString = OWSLocalizedString(
                "THREAD_MERGE_NO_PHONE_NUMBER",
                comment: "A system event shown in a conversation when multiple conversations for the same person have been merged into one. The parameter is replaced with the contact's name (eg John Doe)."
            )
            return String(format: formatString, displayName)
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
