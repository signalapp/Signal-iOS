//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum CVLoadType: Equatable, CustomStringConvertible {
    case loadInitialMapping(focusMessageIdOnOpen: String?,
                            scrollAction: CVScrollAction)
    case loadSameLocation(scrollAction: CVScrollAction)
    case loadOlder
    case loadNewer
    case loadNewest(scrollAction: CVScrollAction)
    case loadPageAroundInteraction(interactionId: String,
                                   scrollAction: CVScrollAction)

    fileprivate var priority: UInt {
        switch self {
        case .loadInitialMapping:
            // We can't do any other load until we do the initial mapping.
            return 4
        case .loadSameLocation:
            return 0
        case .loadOlder:
            // The view is auto-loading.
            return 1
        case .loadNewer:
            // The view is auto-loading.
            return 1
        case .loadNewest:
            // The user explicitly requested this load.
            return 2
        case .loadPageAroundInteraction:
            // The user explicitly requested this load.
            return 3
        }
    }

    var scrollAction: CVScrollAction {
        switch self {
        case .loadInitialMapping(_, let scrollAction):
            return scrollAction
        case .loadSameLocation(let scrollAction):
            return scrollAction
        case .loadOlder, .loadNewer:
            return .none
        case .loadNewest(let scrollAction):
            return scrollAction
        case .loadPageAroundInteraction(_, let scrollAction):
            return scrollAction
        }
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .loadInitialMapping:
            return "loadInitialMapping"
        case .loadSameLocation:
            return "loadSameLocation"
        case .loadOlder:
            return "loadOlder"
        case .loadNewer:
            return "loadNewer"
        case .loadNewest:
            return "loadNewest"
        case .loadPageAroundInteraction:
            return "loadPageAroundInteraction"
        }
    }
}

// MARK: -

struct CVLoadRequest {
    public typealias RequestId = UInt
    let requestId: RequestId
    let loadType: CVLoadType
    let updatedInteractionIds: Set<String>
    let deletedInteractionIds: Set<String>
    let canReuseInteractionModels: Bool
    let canReuseComponentStates: Bool
    let didReset: Bool

    var isInitialLoad: Bool {
        switch loadType {
        case .loadInitialMapping:
            return true
        default:
            return false
        }
    }

    var scrollAction: CVScrollAction { loadType.scrollAction }

    // Now that loads are async, there's some complexity.
    //
    // * Maybe two loads are enqueued before we can do either. We only want
    //   to do one load in this case that reflects the  motive for both loads.
    // * Load requests are stateful, e.g. "reload because interaction X changed".
    //   We need to collect such state.
    // * Load requests might conflict: e.g. "load older" "load newer" or "load
    //   search result X", "load search result Y".  We arbitrate.
    // * After a load lands we often want to scroll to a given interaction.
    //   That's tricky; the user may have "cancelled" that scroll request with
    //   other UX interactions before the load began or while the load was in flight.
    //
    // `CVLoadRequest.Builder` will handle these responsibilties.
    struct Builder {
        private static let requestIdCounter = AtomicUInt()
        let requestId = Self.requestIdCounter.increment()

        // Has any load been requested?
        private var shouldLoad = false

        private var updatedInteractionIds = Set<String>()
        private var deletedInteractionIds = Set<String>()

        private var loadType: CVLoadType = .loadSameLocation(scrollAction: .none)

        private mutating func tryToUpdateLoadType(_ newValue: CVLoadType) {
            guard newValue.priority >= loadType.priority else {
                return
            }

            if case .loadSameLocation = loadType,
               case .loadSameLocation = newValue,
               newValue.scrollAction == .none {
                // Don't lose the scroll action:
                //
                // Don't replace and old .loadSameLocation with a scroll action
                // with a new .loadSameLocation without a scroll action.
                return
            }

            loadType = newValue
        }

        private var canReuseInteractionModels = true
        private var canReuseComponentStates = true
        private var didReset = false

        mutating func reload(updatedInteractionIds: Set<String>,
                             deletedInteractionIds: Set<String>) {
            AssertIsOnMainThread()

            self.updatedInteractionIds.formUnion(updatedInteractionIds)
            self.deletedInteractionIds.formUnion(deletedInteractionIds)

            shouldLoad = true
        }

        mutating func loadInitialMapping(focusMessageIdOnOpen: String?) {
            AssertIsOnMainThread()

            // Configure for initial mapping.
            let scrollAction = CVScrollAction(action: .initialPosition,
                                              isAnimated: false)
            tryToUpdateLoadType(.loadInitialMapping(focusMessageIdOnOpen: focusMessageIdOnOpen,
                                                    scrollAction: scrollAction))
            shouldLoad = true
        }

        mutating func loadOlderItems() {
            AssertIsOnMainThread()

            tryToUpdateLoadType(.loadOlder)
            shouldLoad = true
        }

        mutating func loadNewerItems() {
            AssertIsOnMainThread()

            tryToUpdateLoadType(.loadNewer)
            shouldLoad = true
        }

        mutating func loadAndScrollToNewestItems(isAnimated: Bool) {
            AssertIsOnMainThread()

            let scrollAction = CVScrollAction(action: .bottomOfLoadWindow,
                                              isAnimated: isAnimated)
            tryToUpdateLoadType(.loadNewest(scrollAction: scrollAction))
            shouldLoad = true
        }

        mutating func loadAndScrollToInteraction(interactionId: String,
                                                 onScreenPercentage: CGFloat,
                                                 alignment: ScrollAlignment,
                                                 isAnimated: Bool) {
            AssertIsOnMainThread()

            let scrollAction = CVScrollAction(action: .scrollTo(interactionId: interactionId,
                                                                onScreenPercentage: onScreenPercentage,
                                                                alignment: alignment),
                                              isAnimated: isAnimated)
            tryToUpdateLoadType(.loadPageAroundInteraction(interactionId: interactionId,
                                                           scrollAction: scrollAction))
            shouldLoad = true
        }

        mutating func reload(scrollAction: CVScrollAction?) {
            AssertIsOnMainThread()

            if let scrollAction = scrollAction {
                tryToUpdateLoadType(.loadSameLocation(scrollAction: scrollAction))
            }
            shouldLoad = true
        }

        mutating func reloadWithoutCaches() {
            reload(canReuseInteractionModels: false, canReuseComponentStates: false, didReset: true)
        }

        mutating func reload(canReuseInteractionModels: Bool = true,
                             canReuseComponentStates: Bool = true,
                             didReset: Bool = false) {
            AssertIsOnMainThread()

            self.canReuseInteractionModels = self.canReuseInteractionModels && canReuseInteractionModels
            self.canReuseComponentStates = self.canReuseComponentStates && canReuseComponentStates
            self.didReset = self.didReset || didReset

            shouldLoad = true
        }

        func build() -> CVLoadRequest? {
            AssertIsOnMainThread()

            guard shouldLoad else {
                return nil
            }

            return CVLoadRequest(
                requestId: requestId,
                loadType: loadType,
                updatedInteractionIds: updatedInteractionIds,
                deletedInteractionIds: deletedInteractionIds,
                canReuseInteractionModels: canReuseInteractionModels,
                canReuseComponentStates: canReuseComponentStates,
                didReset: didReset
            )
        }
    }
}
