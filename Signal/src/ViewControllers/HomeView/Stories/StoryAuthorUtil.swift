//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

/// Container for util methods related to story authors.
public enum StoryAuthorUtil {

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
            return String(format: nameFormat, authorShortName, groupName)
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

    static func authorAvatarDataSource(
        for storyMessage: StoryMessage,
        transaction: SDSAnyReadTransaction
    ) throws -> ConversationAvatarDataSource {
        guard !storyMessage.authorAddress.isSystemStoryAddress else {
            return .asset(
                avatar: UIImage(named: "signal-logo-128")?
                    .withRenderingMode(.alwaysTemplate)
                    .asTintedImage(color: .white)?
                    .withBackgroundColor(.ows_accentBlue, insets: UIEdgeInsets(margin: 24)),
                badge: nil
            )
        }
        if let groupId = storyMessage.groupId {
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing group thread for group story")
            }
            return .thread(groupThread)
        } else {
            return .address(storyMessage.authorAddress)
        }
    }
}
