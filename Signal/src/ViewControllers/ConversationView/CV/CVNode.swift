//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum CVMessageCellType: Int, CustomStringConvertible, Equatable {
    case unknown

    // These message cell types all use the default root component.
    case textOnlyMessage
    case audio
    case genericAttachment
    case contactShare
    case bodyMedia
    case viewOnce
    case stickerMessage

    // Most of these other message cell types use a special root view.
    case dateHeader
    case unreadIndicator
    case typingIndicator
    case threadDetails
    case systemMessage

    // MARK: - CustomStringConvertible

    public var description: String {
        get {
            switch self {
            case .unknown: return "unknown"
            case .textOnlyMessage: return "textOnlyMessage"
            case .audio: return "audio"
            case .genericAttachment: return "genericAttachment"
            case .contactShare: return "contactShare"
            case .bodyMedia: return "bodyMedia"
            case .viewOnce: return "viewOnce"
            case .stickerMessage: return "stickerMessage"
            case .dateHeader: return "dateHeader"
            case .unreadIndicator: return "unreadIndicator"
            case .typingIndicator: return "typingIndicator"
            case .threadDetails: return "threadDetails"
            case .systemMessage: return "systemMessage"
            }
        }
    }
}

// MARK: -

// Represents some _renderable_ portion of an Conversation View item.
// It could be the entire item or some part thereof.
@objc
public protocol CVNode {
    var thread: TSThread { get }
    var interaction: TSInteraction { get }
    var messageCellType: CVMessageCellType { get }
    var conversationStyle: ConversationStyle { get }
    var cellMediaCache: NSCache<NSString, AnyObject> { get }
}

// MARK: -

// Represents some _renderable_ portion of an Conversation View item.
// It could be the entire item or some part thereof.
extension CVNode {
    var interactionType: OWSInteractionType { interaction.interactionType() }

    var isIncoming: Bool {
        interaction as? TSIncomingMessage != nil
    }

    var isOutgoing: Bool {
        interaction as? TSOutgoingMessage != nil
    }

    var wasRemotelyDeleted: Bool {
        guard let message = interaction as? TSMessage else {
            return false
        }
        return message.wasRemotelyDeleted
    }

    var hasPerConversationExpiration: Bool {
        guard interaction.interactionType() == .incomingMessage ||
                interaction.interactionType() == .outgoingMessage else {
            return false
        }
        guard let message = interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return false
        }
        return message.hasPerConversationExpiration
    }
}
