//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// This captures all of the state loaded by the CVLoadCoordinator.
//
// It is intended to be an immutable, comprehensive snapshot of all
// loaded state needed to render CVC at a given state of time.
class CVRenderState {

    public static let renderStateId_unknown: UInt = 0

    private static let idCounter = AtomicUInt(1)

    let renderStateId: UInt

    let threadViewModel: ThreadViewModel

    let prevThreadViewModel: ThreadViewModel?
    var isEmptyInitialState: Bool {
        prevThreadViewModel == nil
    }
    var isFirstLoad: Bool {
        if let loadType = self.loadType,
           case CVLoadType.loadInitialMapping = loadType {
            return true
        }
        return false
    }

    // All of CVRenderState's state should be immutable.
    let items: [CVRenderItem]
    let canLoadOlderItems: Bool
    let canLoadNewerItems: Bool

    // The "view state" values that were used when loading this render state.
    let viewStateSnapshot: CVViewStateSnapshot
    let loadType: CVLoadType?

    let loadDate = Date()

    // These values reflect the style and view state at the time
    // was load began. They may be obsolete.
    var conversationStyle: ConversationStyle {
        viewStateSnapshot.conversationStyle
    }

    // TODO: We might want to precompute: interactionIndexMap, focusItemIndex, unreadIndicatorIndex

    var disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration {
        threadViewModel.disappearingMessagesConfiguration
    }

    public let indexPathOfUnreadIndicator: IndexPath?

    private let interactionIdToIndexPathMap: [String: IndexPath]

    public let allIndexPaths: [IndexPath]

    init(threadViewModel: ThreadViewModel,
         prevThreadViewModel: ThreadViewModel?,
         items: [CVRenderItem],
         canLoadOlderItems: Bool,
         canLoadNewerItems: Bool,
         viewStateSnapshot: CVViewStateSnapshot,
         loadType: CVLoadType?) {

        self.threadViewModel = threadViewModel
        self.prevThreadViewModel = prevThreadViewModel
        self.items = items
        self.canLoadOlderItems = canLoadOlderItems
        self.canLoadNewerItems = canLoadNewerItems
        self.viewStateSnapshot = viewStateSnapshot
        self.loadType = loadType

        self.renderStateId = Self.idCounter.increment()

        let messageSection = CVLoadCoordinator.messageSection
        var indexPathOfUnreadIndicator: IndexPath?
        var interactionIdToIndexPathMap = [String: IndexPath]()
        var allIndexPaths = [IndexPath]()
        for (index, item) in items.enumerated() {
            let indexPath = IndexPath(row: index, section: messageSection)
            interactionIdToIndexPathMap[item.interaction.uniqueId] = indexPath
            allIndexPaths.append(indexPath)

            if item.interactionType == .unreadIndicator {
                indexPathOfUnreadIndicator = indexPath
            }
        }
        self.indexPathOfUnreadIndicator = indexPathOfUnreadIndicator
        self.interactionIdToIndexPathMap = interactionIdToIndexPathMap
        self.allIndexPaths = allIndexPaths
    }

    static func defaultRenderState(threadViewModel: ThreadViewModel,
                                   viewStateSnapshot: CVViewStateSnapshot) -> CVRenderState {
        CVRenderState(threadViewModel: threadViewModel,
                      prevThreadViewModel: nil,
                      items: [],
                      canLoadOlderItems: false,
                      canLoadNewerItems: false,
                      viewStateSnapshot: viewStateSnapshot,
                      loadType: nil)
    }

    public func indexPath(forInteractionUniqueId interactionUniqueId: String) -> IndexPath? {
        interactionIdToIndexPathMap[interactionUniqueId]
    }

    public var debugDescription: String {
        isEmptyInitialState ? "empty" : "[items: \(items.count)]"
    }
}
