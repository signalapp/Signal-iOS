//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

/// Container for util methods related to story authors.
public enum StoryUtil: Dependencies {

    static func authorDisplayName(
        for storyMessage: StoryMessage,
        contactsManager: ContactsManagerProtocol,
        useFullNameForLocalAddress: Bool = true,
        transaction: SDSAnyReadTransaction
    ) -> String {
        guard !storyMessage.authorAddress.isSystemStoryAddress else {
            return NSLocalizedString(
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

            let authorShortName: String
            if storyMessage.authorAddress.isLocalAddress {
                authorShortName = CommonStrings.you
            } else {
                authorShortName = contactsManager.shortDisplayName(
                    for: storyMessage.authorAddress,
                    transaction: transaction
                )
            }

            let nameFormat = NSLocalizedString(
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

    static func askToResend(_ message: StoryMessage, in thread: TSThread, from vc: UIViewController) {
        guard !askToConfirmSafetyNumberChangesIfNecessary(for: message, from: vc) else { return }

        let actionSheet = ActionSheetController(message: NSLocalizedString(
            "STORY_RESEND_MESSAGE_ACTION_SHEET",
            comment: "Title for the dialog asking user if they wish to resend a failed story message."
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        actionSheet.addAction(.init(title: CommonStrings.deleteButton, style: .destructive, handler: { _ in
            Self.databaseStorage.write { transaction in
                message.remotelyDelete(for: thread, transaction: transaction)
            }
        }))
        actionSheet.addAction(.init(title: CommonStrings.sendMessage, handler: { _ in
            Self.databaseStorage.write { transaction in
                message.resendMessageToFailedRecipients(transaction: transaction)
            }
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
