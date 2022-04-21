// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionMessagingKit

public struct ThreadViewModel: Equatable {
    public let thread: SessionThread
    public let name: String
    public let unreadCount: UInt
    public let unreadMentionCount: UInt

    public let lastInteraction: Interaction?
    public let lastInteractionDate: Date
    public let lastInteractionText: String?
    public let lastInteractionState: RecipientState.State?
    
    public init(
        thread: SessionThread,
        name: String,
        unreadCount: UInt,
        unreadMentionCount: UInt,
        lastInteraction: Interaction?,
        lastInteractionDate: Date,
        lastInteractionText: String?,
        lastInteractionState: RecipientState.State?
    ) {
        self.thread = thread
        self.name = name
        self.unreadCount = unreadCount
        self.unreadMentionCount = unreadMentionCount
        
        self.lastInteraction = lastInteraction
        self.lastInteractionDate = lastInteractionDate
        self.lastInteractionText = lastInteractionText
        self.lastInteractionState = lastInteractionState
    }
}
