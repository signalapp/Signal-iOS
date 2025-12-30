//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

// Conversation view loads have been decomposed into a series
// of discrete phases. There's a bunch of common state used
// by these load phases that is burdensome to pass around.
// The load contexts gather this state.
struct CVLoadContext: CVItemBuildingContext {

    // Properties
    let loadRequest: CVLoadRequest
    let threadViewModel: ThreadViewModel
    let viewStateSnapshot: CVViewStateSnapshot
    let spoilerState: SpoilerRenderState
    let messageLoader: MessageLoader
    let prevRenderState: CVRenderState?
    let transaction: DBReadTransaction
    let avatarBuilder: CVAvatarBuilder
    let localAci: Aci

    init(
        loadRequest: CVLoadRequest,
        threadViewModel: ThreadViewModel,
        viewStateSnapshot: CVViewStateSnapshot,
        spoilerState: SpoilerRenderState,
        messageLoader: MessageLoader,
        prevRenderState: CVRenderState,
        localAci: Aci,
        transaction: DBReadTransaction,
    ) {
        self.loadRequest = loadRequest
        self.threadViewModel = threadViewModel
        self.viewStateSnapshot = viewStateSnapshot
        self.spoilerState = spoilerState
        self.messageLoader = messageLoader
        self.prevRenderState = prevRenderState
        self.transaction = transaction
        self.avatarBuilder = CVAvatarBuilder(transaction: transaction)
        self.localAci = localAci
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
    var transaction: DBReadTransaction { get }
    var avatarBuilder: CVAvatarBuilder { get }
    var localAci: Aci { get }
    var prevRenderState: CVRenderState? { get }
}

// MARK: -

extension CVItemBuildingContext {
    // Convenience Accessors
    var thread: TSThread { threadViewModel.threadRecord }
    var threadUniqueId: String { thread.uniqueId }
    var conversationStyle: ConversationStyle { viewStateSnapshot.conversationStyle }
    var mediaCache: CVMediaCache { viewStateSnapshot.mediaCache }
}

// MARK: -

struct CVItemBuildingContextImpl: CVItemBuildingContext {
    let prevRenderState: CVRenderState?
    let threadViewModel: ThreadViewModel
    let viewStateSnapshot: CVViewStateSnapshot
    let transaction: DBReadTransaction
    let avatarBuilder: CVAvatarBuilder
    let localAci: Aci
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
    var threadAssociatedData: ThreadAssociatedData { threadViewModel.associatedData }
    var viewStateSnapshot: CVViewStateSnapshot { itemBuildingContext.viewStateSnapshot }
    var conversationStyle: ConversationStyle { itemBuildingContext.conversationStyle }
    var mediaCache: CVMediaCache { itemBuildingContext.mediaCache }
    var transaction: DBReadTransaction { itemBuildingContext.transaction }
    var avatarBuilder: CVAvatarBuilder { itemBuildingContext.avatarBuilder }
    var localAci: Aci { itemBuildingContext.localAci }
}
