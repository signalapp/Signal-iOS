//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

enum MessageRecipient: Equatable {
    case contact(_ address: SignalServiceAddress)
    case group(_ groupThread: TSGroupThread)
}

protocol ConversationItem {
    var messageRecipient: MessageRecipient { get }
    var title: String { get }
    var image: UIImage? { get }
    var isBlocked: Bool { get }
    var disappearingMessagesConfig: OWSDisappearingMessagesConfiguration? { get }
}

struct RecentConversationItem {
    enum ItemType {
        case contact(_ item: ContactConversationItem)
        case group(_ item: GroupConversationItem)
    }

    let backingItem: ItemType
    var unwrapped: ConversationItem {
        switch backingItem {
        case .contact(let contactItem):
            return contactItem
        case .group(let groupItem):
            return groupItem
        }
    }
}

extension RecentConversationItem: ConversationItem {
    var messageRecipient: MessageRecipient {
        return unwrapped.messageRecipient
    }

    var title: String {
        return unwrapped.title
    }

    var image: UIImage? {
        return unwrapped.image
    }

    var isBlocked: Bool {
        return unwrapped.isBlocked
    }

    var disappearingMessagesConfig: OWSDisappearingMessagesConfiguration? {
        return unwrapped.disappearingMessagesConfig
    }
}

struct ContactConversationItem {
    let address: SignalServiceAddress
    let isBlocked: Bool
    let disappearingMessagesConfig: OWSDisappearingMessagesConfiguration?

    // MARK: - Dependencies

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }
}

extension ContactConversationItem: ConversationItem {
    var messageRecipient: MessageRecipient {
        return .contact(address)
    }

    var title: String {
        guard !address.isLocalAddress else {
            return MessageStrings.noteToSelf
        }

        return self.contactsManager.displayName(for: address)
    }

    var image: UIImage? {
        // TODO initials, etc.
        return OWSProfileManager.shared().profileAvatar(for: address)
    }
}

struct GroupConversationItem {
    let groupThread: TSGroupThread
    let isBlocked: Bool
    let disappearingMessagesConfig: OWSDisappearingMessagesConfiguration?

    var groupModel: TSGroupModel {
        return groupThread.groupModel
    }
}

extension GroupConversationItem: ConversationItem {
    var messageRecipient: MessageRecipient {
        return .group(groupThread)
    }

    var title: String {
        return groupThread.groupNameOrDefault
    }

    var image: UIImage? {
        return OWSAvatarBuilder.buildImage(thread: groupThread, diameter: kStandardAvatarSize)
    }
}
