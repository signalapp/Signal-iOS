//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// Conversation view loads have been decomposed into a series
// of discrete phases. There's a bunch of common state used
// by these load phases that is burdensome to pass around.
// The load contexts gather this state.
struct CVLoadContext: CVItemBuildingContext {

    // Properties
    let loadRequest: CVLoadRequest
    let threadViewModel: ThreadViewModel
    let viewStateSnapshot: CVViewStateSnapshot
    let messageMapping: CVMessageMapping
    let prevRenderState: CVRenderState
    let transaction: SDSAnyReadTransaction
    let avatarBuilder: CVAvatarBuilder

    init(loadRequest: CVLoadRequest,
         threadViewModel: ThreadViewModel,
         viewStateSnapshot: CVViewStateSnapshot,
         messageMapping: CVMessageMapping,
         prevRenderState: CVRenderState,
         transaction: SDSAnyReadTransaction) {

        self.loadRequest = loadRequest
        self.threadViewModel = threadViewModel
        self.viewStateSnapshot = viewStateSnapshot
        self.messageMapping = messageMapping
        self.prevRenderState = prevRenderState
        self.transaction = transaction
        self.avatarBuilder = CVAvatarBuilder(transaction: transaction)
    }

    // Convenience Accessors
    var thread: TSThread { threadViewModel.threadRecord }
}

// MARK: -

// Conversation view loads have been decomposed into a series
// of discrete phases. There's a bunch of common state used
// by these load phases that is burdensome to pass around.
// The load contexts gather this state; CVItemBuilding provides
// convenient access to its contents.
protocol CVItemBuildingContext {
    // Properties
    var threadViewModel: ThreadViewModel { get }
    var viewStateSnapshot: CVViewStateSnapshot { get }
    var transaction: SDSAnyReadTransaction { get }
    var avatarBuilder: CVAvatarBuilder { get }
}

// MARK: -

extension CVItemBuildingContext {
    // Convenience Accessors
    var thread: TSThread { threadViewModel.threadRecord }
    var threadUniqueId: String { thread.uniqueId }
    var conversationStyle: ConversationStyle { viewStateSnapshot.conversationStyle }
    var cellMediaCache: NSCache<NSString, AnyObject> { viewStateSnapshot.cellMediaCache }
}

// MARK: -

struct CVItemBuildingContextImpl: CVItemBuildingContext {
    let threadViewModel: ThreadViewModel
    let viewStateSnapshot: CVViewStateSnapshot
    let transaction: SDSAnyReadTransaction
    let avatarBuilder: CVAvatarBuilder
}

// MARK: -

protocol CVItemBuilding {
    var itemBuildingContext: CVItemBuildingContext { get }
}

// MARK: -

extension CVItemBuilding {
    // Convenience Accessors
    var threadViewModel: ThreadViewModel { itemBuildingContext.threadViewModel }
    var thread: TSThread { itemBuildingContext.thread }
    var viewStateSnapshot: CVViewStateSnapshot { itemBuildingContext.viewStateSnapshot }
    var conversationStyle: ConversationStyle { itemBuildingContext.conversationStyle }
    var cellMediaCache: NSCache<NSString, AnyObject> { itemBuildingContext.cellMediaCache }
    var transaction: SDSAnyReadTransaction { itemBuildingContext.transaction }
    var avatarBuilder: CVAvatarBuilder { itemBuildingContext.avatarBuilder }
}
