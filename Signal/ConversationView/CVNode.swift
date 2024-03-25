//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public enum CVMessageCellType: Int, CustomStringConvertible, Equatable {
    case unknown

    // These message cell types all use the default root component.
    case textOnlyMessage
    case audio
    case genericAttachment
    case paymentAttachment
    case contactShare
    case bodyMedia
    case viewOnce
    case stickerMessage
    case quoteOnlyMessage
    case giftBadge

    // Most of these other message cell types use a special root view.
    case dateHeader
    case unreadIndicator
    case typingIndicator
    case threadDetails
    case systemMessage
    case unknownThreadWarning
    case defaultDisappearingMessageTimer

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .unknown: return "unknown"
        case .textOnlyMessage: return "textOnlyMessage"
        case .quoteOnlyMessage: return "quoteOnlyMessage"
        case .audio: return "audio"
        case .genericAttachment: return "genericAttachment"
        case .paymentAttachment: return "paymentAttachment"
        case .contactShare: return "contactShare"
        case .bodyMedia: return "bodyMedia"
        case .viewOnce: return "viewOnce"
        case .stickerMessage: return "stickerMessage"
        case .giftBadge: return "giftBadge"
        case .dateHeader: return "dateHeader"
        case .unreadIndicator: return "unreadIndicator"
        case .typingIndicator: return "typingIndicator"
        case .threadDetails: return "threadDetails"
        case .systemMessage: return "systemMessage"
        case .unknownThreadWarning: return "unknownThreadWarning"
        case .defaultDisappearingMessageTimer: return "defaultDisappearingMessageTimer"
        }
    }
}

// MARK: -

// Represents some _renderable_ portion of an Conversation View item.
// It could be the entire item or some part thereof.
public protocol CVNode {
    var thread: TSThread { get }
    var interaction: TSInteraction { get }
    var messageCellType: CVMessageCellType { get }
    var conversationStyle: ConversationStyle { get }
    var mediaCache: CVMediaCache { get }
}

// MARK: -

// Represents some _renderable_ portion of an Conversation View item.
// It could be the entire item or some part thereof.
extension CVNode {
    var interactionType: OWSInteractionType { interaction.interactionType }

    var isIncoming: Bool {
        interaction as? TSIncomingMessage != nil
    }

    var isOutgoing: Bool {
        interaction as? TSOutgoingMessage != nil
    }

    var wasNotCreatedLocally: Bool {
        (interaction as? TSOutgoingMessage)?.wasNotCreatedLocally == true
    }

    var wasRemotelyDeleted: Bool {
        guard let message = interaction as? TSMessage else {
            return false
        }
        return message.wasRemotelyDeleted
    }

    var hasPerConversationExpiration: Bool {
        guard interaction.interactionType == .incomingMessage ||
                interaction.interactionType == .outgoingMessage else {
            return false
        }
        guard let message = interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return false
        }
        return message.hasPerConversationExpiration
    }
}
