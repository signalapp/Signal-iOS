//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension TSInfoMessage {
    /// The display names we'll use before learning someone's profile key.
    public enum DisplayNameBeforeLearningProfileName: Equatable {
        case phoneNumber(String)
        case username(String)
    }

    static func insertLearnedProfileNameMessage(
        serviceId: ServiceId,
        displayNameBefore: DisplayNameBeforeLearningProfileName,
        tx: any DBWriteTransaction
    ) {
        let threadStore = DependenciesBridge.shared.threadStore
        let interactionStore = DependenciesBridge.shared.interactionStore

        guard let contactThread = threadStore.fetchContactThreads(
            serviceId: serviceId,
            tx: tx
        ).first else { return }

        let infoMessage: TSInfoMessage = .makeForLearnedProfileName(
            contactThread: contactThread,
            displayNameBefore: displayNameBefore
        )
        interactionStore.insertInteraction(infoMessage, tx: tx)
    }

    static func makeForLearnedProfileName(
        contactThread: TSContactThread,
        timestamp: UInt64 = MessageTimestampGenerator.sharedInstance.generateTimestamp(),
        displayNameBefore: DisplayNameBeforeLearningProfileName
    ) -> TSInfoMessage {
        let infoMessageUserInfo: [InfoMessageUserInfoKey: Any] = switch displayNameBefore {
        case .phoneNumber(let phoneNumber):
            [.phoneNumberDisplayNameBeforeLearningProfileName: phoneNumber]
        case .username(let username):
            [.usernameDisplayNameBeforeLearningProfileName: username]
        }

        return TSInfoMessage(
            thread: contactThread,
            messageType: .learnedProfileName,
            timestamp: timestamp,
            infoMessageUserInfo: infoMessageUserInfo
        )
    }
}

public extension TSInfoMessage {
    var displayNameBeforeLearningProfileName: DisplayNameBeforeLearningProfileName? {
        if let phoneNumber: String = infoMessageValue(forKey: .phoneNumberDisplayNameBeforeLearningProfileName) {
            return .phoneNumber(phoneNumber)
        } else if let username: String = infoMessageValue(forKey: .usernameDisplayNameBeforeLearningProfileName) {
            return .username(username)
        }

        return nil
    }

    @objc
    func learnedProfileNameDescription(tx: SDSAnyReadTransaction) -> String {
        guard let displayNameBeforeLearningProfileName else {
            return ""
        }

        let format = OWSLocalizedString(
            "INFO_MESSAGE_LEARNED_PROFILE_KEY",
            comment: "When you start a chat with someone and then later learn their profile name, we insert an in-chat message with this string to record the identifier you originally used to contact them. Embeds {{ the identifier, either a phone number or a username }}."
        )

        switch displayNameBeforeLearningProfileName {
        case .phoneNumber(let phoneNumber):
            return String(format: format, phoneNumber)
        case .username(let username):
            return String(format: format, username)
        }
    }
}
