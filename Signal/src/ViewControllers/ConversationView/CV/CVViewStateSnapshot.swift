//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// This captures the CV view state that can affect the load.
// It is used when building, measuring & configuring components and their views.
struct CVViewStateSnapshot: Dependencies {

    let textExpansion: CVTextExpansion
    let spoilerReveal: SpoilerRevealState.Snapshot
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

    let uiMode: ConversationUIMode
    let previousUIMode: ConversationUIMode

    public var isShowingSelectionUI: Bool { uiMode.hasSelectionUI }
    public var wasShowingSelectionUI: Bool { previousUIMode.hasSelectionUI }

    let searchText: String?

    let oldestUnreadMessageSortId: UInt64?

    let currentCallThreadId: String?

    static func snapshot(
        viewState: CVViewState,
        typingIndicatorsSender: SignalServiceAddress?,
        oldestUnreadMessageSortId: UInt64?,
        previousViewStateSnapshot: CVViewStateSnapshot?
    ) -> CVViewStateSnapshot {
        CVViewStateSnapshot(
            textExpansion: viewState.textExpansion.copy(),
            spoilerReveal: viewState.spoilerReveal.snapshot(),
            messageSwipeActionState: viewState.messageSwipeActionState.copy(),
            coreState: viewState.asCoreState,
            typingIndicatorsSender: typingIndicatorsSender,
            uiMode: viewState.uiMode,
            previousUIMode: previousViewStateSnapshot?.uiMode ?? .normal,
            searchText: viewState.lastSearchedText,
            oldestUnreadMessageSortId: oldestUnreadMessageSortId,
            currentCallThreadId: callService.currentCall?.thread.uniqueId
        )
    }

    static func mockSnapshotForStandaloneItems(
        coreState: CVCoreState,
        spoilerReveal: SpoilerRevealState
    ) -> CVViewStateSnapshot {
        CVViewStateSnapshot(
            textExpansion: CVTextExpansion(),
            spoilerReveal: spoilerReveal.snapshot(),
            messageSwipeActionState: CVMessageSwipeActionState(),
            coreState: coreState,
            typingIndicatorsSender: nil,
            uiMode: .normal,
            previousUIMode: .normal,
            searchText: nil,
            oldestUnreadMessageSortId: nil,
            currentCallThreadId: nil
        )
    }
}
