//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

/// Container for util methods related to story authors.
public enum StoryUtil: Dependencies {

    static func authorDisplayName(
        for storyMessage: StoryMessage,
        contactsManager: ContactsManagerProtocol,
        useFullNameForLocalAddress: Bool = true,
        useShortGroupName: Bool = true,
        transaction: SDSAnyReadTransaction
    ) -> String {
        guard !storyMessage.authorAddress.isSystemStoryAddress else {
            return OWSLocalizedString(
                "SYSTEM_ADDRESS_NAME",
                comment: "Name to display for the 'system' sender, e.g. for release notes and the onboarding story"
            )
        }
        if let groupId = storyMessage.groupId {
            let groupName: String = {
                guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                    owsFailDebug("Missing group thread for group story")
                    return TSGroupThread.defaultGroupName
                }
                return groupThread.groupNameOrDefault
            }()

            if useShortGroupName { return groupName }

            let authorShortName: String
            if storyMessage.authorAddress.isLocalAddress {
                authorShortName = CommonStrings.you
            } else {
                authorShortName = contactsManager.shortDisplayName(
                    for: storyMessage.authorAddress,
                    transaction: transaction
                )
            }

            let nameFormat = OWSLocalizedString(
                "GROUP_STORY_NAME_FORMAT",
                comment: "Name for a group story on the stories list. Embeds {author's name}, {group name}"
            )
            return String.localizedStringWithFormat(nameFormat, authorShortName, groupName)
        } else {
            if !useFullNameForLocalAddress && storyMessage.authorAddress.isLocalAddress {
                return CommonStrings.you
            }
            return contactsManager.displayName(
                for: storyMessage.authorAddress,
                transaction: transaction
            )
        }
    }

    /// Avatar for the _context_ of a story message. e.g. the group avatar if a group thread story, or the author's avatar otherwise.
    static func contextAvatarDataSource(
        for storyMessage: StoryMessage,
        transaction: SDSAnyReadTransaction
    ) throws -> ConversationAvatarDataSource {
        guard let groupId = storyMessage.groupId else {
            return try authorAvatarDataSource(for: storyMessage, transaction: transaction)
        }
        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Missing group thread for group story")
        }
        return .thread(groupThread)
    }

    /// Avatar for the author of a story message, regardless of its context.
    static func authorAvatarDataSource(
        for storyMessage: StoryMessage,
        transaction: SDSAnyReadTransaction
    ) throws -> ConversationAvatarDataSource {
        guard !storyMessage.authorAddress.isSystemStoryAddress else {
            return systemStoryAvatar
        }
        return .address(storyMessage.authorAddress)
    }

    private static var systemStoryAvatar: ConversationAvatarDataSource {
        return .asset(
            avatar: UIImage(named: "signal-logo-128")?
                .withRenderingMode(.alwaysTemplate)
                .asTintedImage(color: .white)?
                .withBackgroundColor(.ows_accentBlue, insets: UIEdgeInsets(margin: 24)),
            badge: nil
        )
    }

    static func askToResend(_ message: StoryMessage, in thread: TSThread, from vc: UIViewController, completion: @escaping () -> Void = {}) {
        guard !askToConfirmSafetyNumberChangesIfNecessary(for: message, from: vc) else { return }

        let title: String
        if message.hasSentToAnyRecipients {
            title = OWSLocalizedString(
                "STORY_RESEND_PARTIALLY_FAILED_MESSAGE_ACTION_SHEET",
                comment: "Title for the dialog asking user if they wish to resend a partially failed story message."
            )
        } else {
            title = OWSLocalizedString(
                "STORY_RESEND_FAILED_MESSAGE_ACTION_SHEET",
                comment: "Title for the dialog asking user if they wish to resend a failed story message."
            )
        }

        let actionSheet = ActionSheetController(message: title)
        actionSheet.addAction(.init(title: CommonStrings.deleteButton, style: .destructive, handler: { _ in
            Self.databaseStorage.write { transaction in
                message.remotelyDelete(for: thread, transaction: transaction)
            }
            completion()
        }))
        actionSheet.addAction(.init(title: CommonStrings.sendMessage, handler: { _ in
            Self.databaseStorage.write { transaction in
                message.resendMessageToFailedRecipients(transaction: transaction)
            }
            completion()
        }))
        actionSheet.addAction(.init(title: CommonStrings.cancelButton, style: .cancel, handler: { _ in
            completion()
        }))
        vc.presentActionSheet(actionSheet, animated: true)
    }

    private static func askToConfirmSafetyNumberChangesIfNecessary(for message: StoryMessage, from vc: UIViewController) -> Bool {
        let recipientsWithChangedSafetyNumber = message.failedRecipientAddresses(errorCode: UntrustedIdentityError.errorCode)
        guard !recipientsWithChangedSafetyNumber.isEmpty else { return false }

        let sheet = SafetyNumberConfirmationSheet(
            addressesToConfirm: recipientsWithChangedSafetyNumber,
            confirmationText: MessageStrings.sendButton
        ) { confirmedSafetyNumberChange in
            guard confirmedSafetyNumberChange else { return }
            Self.databaseStorage.write { transaction in
                message.resendMessageToFailedRecipients(transaction: transaction)
            }
        }
        vc.present(sheet, animated: true)

        return true
    }
}
