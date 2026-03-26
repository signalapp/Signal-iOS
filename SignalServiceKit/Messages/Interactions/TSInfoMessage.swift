//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension TSInfoMessage {

    // MARK: - Convenience initializers

    public convenience init(
        thread: TSThread,
        messageType: TSInfoMessageType,
        timestamp: UInt64 = MessageTimestampGenerator.sharedInstance.generateTimestamp(),
        expireTimerVersion: UInt32? = nil,
        expiresInSeconds: UInt32? = nil,
        infoMessageUserInfo: [InfoMessageUserInfoKey: Any]? = nil,
    ) {
        self.init(
            thread: thread,
            timestamp: timestamp,
            serverGuid: nil,
            messageType: messageType,
            expireTimerVersion: expireTimerVersion as NSNumber?,
            expiresInSeconds: expiresInSeconds ?? 0,
            infoMessageUserInfo: infoMessageUserInfo,
        )
    }

    @objc
    func _infoMessagePreviewText(tx: DBReadTransaction) -> String {
        switch messageType {
        case .typeLocalUserEndedSession:
            fallthrough
        case .typeRemoteUserEndedSession:
            return OWSLocalizedString("SECURE_SESSION_RESET", comment: "")
        case .typeUnsupportedMessage:
            return OWSLocalizedString("UNSUPPORTED_ATTACHMENT", comment: "")
        case .userNotRegistered:
            if let unregisteredAddress, unregisteredAddress.isValid {
                let recipientName = SSKEnvironment.shared.contactManagerRef.displayNameString(for: unregisteredAddress, transaction: tx)
                return String(
                    format: OWSLocalizedString(
                        "ERROR_UNREGISTERED_USER_FORMAT",
                        comment: "Format string for 'unregistered user' error. Embeds {{the unregistered user's name or signal id}}.",
                    ),
                    recipientName,
                )
            } else {
                return OWSLocalizedString("CONTACT_DETAIL_COMM_TYPE_INSECURE", comment: "")
            }
        case .typeGroupQuit:
            return OWSLocalizedString("GROUP_YOU_LEFT", comment: "")
        case .typeGroupUpdate:
            return self.groupUpdateDescription(tx: tx).string
        case .addToContactsOffer:
            return OWSLocalizedString("ADD_TO_CONTACTS_OFFER", comment: "Message shown in conversation view that offers to add an unknown user to your phone's contacts.")
        case .verificationStateChange:
            return OWSLocalizedString("VERIFICATION_STATE_CHANGE_GENERIC", comment: "Generic message indicating that verification state changed for a given user.")
        case .addUserToProfileWhitelistOffer:
            return OWSLocalizedString("ADD_USER_TO_PROFILE_WHITELIST_OFFER", comment: "Message shown in conversation view that offers to share your profile with a user.")
        case .addGroupToProfileWhitelistOffer:
            return OWSLocalizedString("ADD_GROUP_TO_PROFILE_WHITELIST_OFFER", comment: "Message shown in conversation view that offers to share your profile with a group.")
        case .typeDisappearingMessagesUpdate:
            break
        case .unknownProtocolVersion:
            break
        case .userJoinedSignal:
            let address = TSContactThread.contactAddress(fromThreadId: self.uniqueThreadId, transaction: tx)
            let recipientName = SSKEnvironment.shared.contactManagerRef.displayNameString(for: address!, transaction: tx)
            let format = OWSLocalizedString("INFO_MESSAGE_USER_JOINED_SIGNAL_BODY_FORMAT", comment: "Shown in inbox and conversation when a user joins Signal, embeds the new user's {{contact name}}")
            return String(format: format, recipientName)
        case .syncedThread:
            return ""
        case .profileUpdate:
            return self.profileChangeDescription(tx: tx)
        case .phoneNumberChange:
            guard let aci = self.phoneNumberChangeInfoAci() else {
                owsFailDebug("Invalid info message")
                return ""
            }
            let address = SignalServiceAddress(aci.wrappedAciValue)
            let userName = SSKEnvironment.shared.contactManagerRef.displayNameString(for: address, transaction: tx)
            let format = OWSLocalizedString(
                "INFO_MESSAGE_USER_CHANGED_PHONE_NUMBER_FORMAT",
                comment: "Indicates that another user has changed their phone number. Embeds: {{ the user's name}}",
            )
            return String(format: format, userName)
        case .recipientHidden:
            /// This does not control whether to show the info message in the chat
            /// preview. To control that, see ``TSInteraction.shouldAppearInInbox``.
            let address = TSContactThread.contactAddress(fromThreadId: self.uniqueThreadId, transaction: tx)
            if DependenciesBridge.shared.recipientHidingManager.isHiddenAddress(address!, tx: tx) {
                return OWSLocalizedString(
                    "INFO_MESSAGE_CONTACT_REMOVED",
                    comment: "Indicates that the recipient has been removed from the current user's contacts and that messaging them will re-add them.",
                )
            } else {
                return OWSLocalizedString(
                    "INFO_MESSAGE_CONTACT_REINSTATED",
                    comment: "Indicates that a previously-removed recipient has been added back to the current user's contacts.",
                )
            }
        case .paymentsActivationRequest:
            return self.paymentsActivationRequestDescription(tx: tx) ?? ""
        case .paymentsActivated:
            return self.paymentsActivatedDescription(tx: tx) ?? ""
        case .threadMerge:
            return self.threadMergeDescription(tx: tx)
        case .sessionSwitchover:
            return self.sessionSwitchoverDescription(tx: tx)
        case .reportedSpam:
            return OWSLocalizedString(
                "INFO_MESSAGE_REPORTED_SPAM",
                comment: "Shown when a user reports a conversation as spam.",
            )
        case .learnedProfileName:
            return self.learnedProfileNameDescription(tx: tx)
        case .blockedOtherUser:
            return OWSLocalizedString(
                "INFO_MESSAGE_BLOCKED_OTHER_USER",
                comment: "An info message inserted into a 1:1 chat when you block another user.",
            )
        case .blockedGroup:
            return OWSLocalizedString(
                "INFO_MESSAGE_BLOCKED_GROUP",
                comment: "An info message inserted into a group chat when you block the group.",
            )
        case .unblockedOtherUser:
            return OWSLocalizedString(
                "INFO_MESSAGE_UNBLOCKED_OTHER_USER",
                comment: "An info message inserted into a 1:1 chat when you unblock another user.",
            )
        case .unblockedGroup:
            return OWSLocalizedString(
                "INFO_MESSAGE_UNBLOCKED_GROUP",
                comment: "An info message inserted into a group chat when you unblock the group.",
            )
        case .acceptedMessageRequest:
            return OWSLocalizedString(
                "INFO_MESSAGE_ACCEPTED_MESSAGE_REQUEST",
                comment: "An info message inserted into the chat when you accept a message request, in a 1:1 or group chat.",
            )
        case .typeEndPoll:
            return self.endPollDescription(transaction: tx) ?? ""
        case .typePinnedMessage:
            return self.pinnedMessageDescription(transaction: tx) ?? ""
        }

        owsFailDebug("Unknown info message type")
        return ""
    }

    // MARK: - InfoMessageUserInfo

    func infoMessageValue<T>(forKey key: InfoMessageUserInfoKey) -> T? {
        guard let value = infoMessageUserInfo?[key] as? T else {
            return nil
        }

        return value
    }

    func setInfoMessageValue(_ value: Any, forKey key: InfoMessageUserInfoKey) {
        if self.infoMessageUserInfo != nil {
            self.infoMessageUserInfo![key] = value
        } else {
            self.infoMessageUserInfo = [key: value]
        }
    }
}
