//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class CVRenderItem: NSObject {
    public let itemModel: CVItemModel

    public var componentState: CVComponentState { itemModel.componentState }
    public var itemViewState: CVItemViewState { itemModel.itemViewState }

    public let rootComponent: CVRootComponent

    public let cellMeasurement: CVCellMeasurement
    public var cellSize: CGSize { cellMeasurement.cellSize }

    private let incomingMessageAuthorAddress: SignalServiceAddress?

    public var cellReuseIdentifier: String {
        rootComponent.cellReuseIdentifier.rawValue
    }

    public var interaction: TSInteraction {
        itemModel.interaction
    }

    public var interactionUniqueId: String { interaction.uniqueId }
    public var interactionType: OWSInteractionType { interaction.interactionType }

    init(itemModel: CVItemModel,
         rootComponent: CVRootComponent,
         cellMeasurement: CVCellMeasurement) {
        self.itemModel = itemModel
        self.rootComponent = rootComponent
        self.cellMeasurement = cellMeasurement

        // This value is used in a particularly hot code path.
        if let incomingMessage = itemModel.interaction as? TSIncomingMessage {
            self.incomingMessageAuthorAddress = incomingMessage.authorAddress
        } else {
            self.incomingMessageAuthorAddress = nil
        }
    }

    enum UpdateMode {
        case equal
        case stateChanged
        // The appearance of items depends on its neighbors,
        // so an item's appearance can change even though
        // its state didn't change.
        case appearanceChanged
    }

    func updateMode(other: CVRenderItem) -> UpdateMode {
        guard interactionUniqueId == other.interactionUniqueId else {
            // We should only compare two items that represent the same interaction.
            owsFailDebug("Unexpected other item.")
            return .stateChanged
        }
        guard componentState == other.componentState else {
            return .stateChanged
        }
        guard itemViewState == other.itemViewState else {
            return .appearanceChanged
        }
        guard itemModel.conversationStyle.isEqualForCellRendering(other.itemModel.conversationStyle) else {
            return .appearanceChanged
        }
        guard cellSize == other.cellSize else {
            Logger.verbose("cellSize: \(cellSize) != \(other.cellSize)")
            owsFailDebug("cellSize does not match.")
            return .stateChanged
        }
        guard cellMeasurement == other.cellMeasurement else {
            Logger.verbose("cellMeasurement: \(cellMeasurement) != \(other.cellMeasurement)")
            owsFailDebug("cellMeasurement does not match.")
            return .stateChanged
        }
        return .equal
    }

    var interactionTypeName: String {
        NSStringFromOWSInteractionType(interaction.interactionType)
    }

    public override var debugDescription: String {
        "\(interactionUniqueId) \(interactionTypeName)"
    }

    public var reactionState: InteractionReactionState? {
        componentState.reactions?.reactionState
    }
}

// MARK: -

extension CVRenderItem: ConversationViewLayoutItem {

    public func vSpacing(previousLayoutItem: ConversationViewLayoutItem) -> CGFloat {
        guard let previousLayoutItem = previousLayoutItem as? CVRenderItem else {
            owsFailDebug("Invalid previousLayoutItem.")
            return 0
        }

        let interaction = itemModel.interaction
        let previousInteraction = previousLayoutItem.itemModel.interaction

        switch interaction.interactionType {
        case .dateHeader, .unreadIndicator:
            return ConversationStyle.defaultMessageSpacing
        case .incomingMessage:
            switch previousInteraction.interactionType {
            case .incomingMessage:
                // Only use compact spacing within a cluster
                // of messages from the same author.
                if !itemViewState.isFirstInCluster,
                   let selfAuthorAddress = self.incomingMessageAuthorAddress,
                   let prevAuthorAddress = previousLayoutItem.incomingMessageAuthorAddress,
                   selfAuthorAddress == prevAuthorAddress {
                    return ConversationStyle.compactMessageSpacing
                }
                return ConversationStyle.defaultMessageSpacing
            case .call, .info, .error:
                return ConversationStyle.systemMessageSpacing
            default:
                return ConversationStyle.defaultMessageSpacing
            }
        case .outgoingMessage:
            switch previousInteraction.interactionType {
            case .outgoingMessage:
                // Only use compact spacing within a cluster.
                if itemViewState.isFirstInCluster {
                    return ConversationStyle.defaultMessageSpacing
                } else {
                    return ConversationStyle.compactMessageSpacing
                }
            case .call, .info, .error:
                return ConversationStyle.systemMessageSpacing
            default:
                return ConversationStyle.defaultMessageSpacing
            }
        case .call, .info, .error:
            if previousInteraction.interactionType == interaction.interactionType {
                switch previousInteraction.interactionType {
                case .error:
                    if let errorMessage = interaction as? TSErrorMessage,
                       let previousErrorMessage = previousInteraction as? TSErrorMessage,
                       (errorMessage.errorType == .nonBlockingIdentityChange
                            || previousErrorMessage.errorType != errorMessage.errorType) {
                        return ConversationStyle.defaultMessageSpacing
                    }
                    return 0
                case .info:
                    if let infoMessage = interaction as? TSInfoMessage,
                       let previousInfoMessage = previousInteraction as? TSInfoMessage,
                       (infoMessage.messageType == .verificationStateChange
                            || previousInfoMessage.messageType != infoMessage.messageType) {
                        return ConversationStyle.defaultMessageSpacing
                    }
                    return 0
                case .call:
                    return 0
                default:
                    return ConversationStyle.defaultMessageSpacing
                }
            } else if previousInteraction.interactionType == .outgoingMessage
                        || previousInteraction.interactionType == .incomingMessage {
                return ConversationStyle.systemMessageSpacing
            } else {
                return ConversationStyle.defaultMessageSpacing
            }
        default:
            return ConversationStyle.defaultMessageSpacing
        }
    }

    public var canBeUsedForContinuity: Bool {
        ConversationViewLayout.canInteractionBeUsedForScrollContinuity(itemModel.interaction)
    }

    public var isDateHeader: Bool {
        itemModel.interaction.interactionType == .dateHeader
    }
}
