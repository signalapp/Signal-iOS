//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// This captures the CV view state that can affect the load.
// It is used when building, measuring & configuring components and their views.
struct CVViewStateSnapshot: Dependencies {

    let textExpansion: CVTextExpansion
    let messageSwipeActionState: CVMessageSwipeActionState

    // We can only measure (configure) with a given ConversationStyle.
    // So we need to capture the ConversationStyle at the time the
    // update is initiated. If the ConversationStyle has changed by
    // the time the update is delivered, we should reject the update
    // and request a new one.
    let coreState: CVCoreState
    public var conversationStyle: ConversationStyle { coreState.conversationStyle }
    public var mediaCache: CVMediaCache { coreState.mediaCache }

    // TODO: We need to determine exactly what the desired behavior here is.
    let collapseCutoffDate = Date()

    let typingIndicatorsSender: SignalServiceAddress?

    let isShowingSelectionUI: Bool

    let searchText: String?

    let hasClearedUnreadMessagesIndicator: Bool

    let currentCallThreadId: String?

    static func snapshot(viewState: CVViewState,
                         typingIndicatorsSender: SignalServiceAddress?,
                         hasClearedUnreadMessagesIndicator: Bool) -> CVViewStateSnapshot {
        CVViewStateSnapshot(textExpansion: viewState.textExpansion.copy(),
                            messageSwipeActionState: viewState.messageSwipeActionState.copy(),
                            coreState: viewState.asCoreState,
                            typingIndicatorsSender: typingIndicatorsSender,
                            isShowingSelectionUI: viewState.isShowingSelectionUI,
                            searchText: viewState.lastSearchedText,
                            hasClearedUnreadMessagesIndicator: hasClearedUnreadMessagesIndicator,
                            currentCallThreadId: callService.currentCall?.thread.uniqueId)
    }

    static func mockSnapshotForStandaloneItems(coreState: CVCoreState) -> CVViewStateSnapshot {
        CVViewStateSnapshot(textExpansion: CVTextExpansion(),
                            messageSwipeActionState: CVMessageSwipeActionState(),
                            coreState: coreState,
                            typingIndicatorsSender: nil,
                            isShowingSelectionUI: false,
                            searchText: nil,
                            hasClearedUnreadMessagesIndicator: false,
                            currentCallThreadId: nil)
    }
}
