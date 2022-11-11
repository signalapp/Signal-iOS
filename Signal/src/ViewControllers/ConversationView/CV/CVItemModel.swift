//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Represents a single item in the conversation history.
// Could be a date header or a unread indicator.
//
// All of the state in this class should be immutable.
public class CVItemModel: NSObject {
    public let interaction: TSInteraction
    public let thread: TSThread
    public let threadAssociatedData: ThreadAssociatedData

    // The item state loaded from the database.
    public let componentState: CVComponentState

    // The item state determined by context, view state.
    public let itemViewState: CVItemViewState

    public var messageCellType: CVMessageCellType { componentState.messageCellType }

    // We can only measure (configure) with a given ConversationStyle.
    // So we need to capture the ConversationStyle at the time the
    // update is initiated. If the ConversationStyle has changed by
    // the time the update is delivered, we should reject the update
    // and request a new one.
    private let coreState: CVCoreState
    public var conversationStyle: ConversationStyle { coreState.conversationStyle }
    public var mediaCache: CVMediaCache { coreState.mediaCache }

    public var itemModel: CVItemModel {
        self
    }

    init(interaction: TSInteraction,
         thread: TSThread,
         threadAssociatedData: ThreadAssociatedData,
         componentState: CVComponentState,
         itemViewState: CVItemViewState,
         coreState: CVCoreState) {

        self.interaction = interaction
        self.thread = thread
        self.threadAssociatedData = threadAssociatedData
        self.componentState = componentState
        self.itemViewState = itemViewState
        self.coreState = coreState
    }
}
