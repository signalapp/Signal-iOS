//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// This entity performs a single load.
public class CVLoader: NSObject {

    static var verboseLogging: Bool {
        false && DebugFlags.internalLogging
    }

    private let threadUniqueId: String
    private let loadRequest: CVLoadRequest
    private let viewStateSnapshot: CVViewStateSnapshot
    private let spoilerReveal: SpoilerRevealState
    private let prevRenderState: CVRenderState
    private let messageMapping: CVMessageMapping

    private let benchSteps = BenchSteps(title: "CVLoader")

    required init(
        threadUniqueId: String,
        loadRequest: CVLoadRequest,
        viewStateSnapshot: CVViewStateSnapshot,
        spoilerReveal: SpoilerRevealState,
        prevRenderState: CVRenderState,
        messageMapping: CVMessageMapping
    ) {
        self.threadUniqueId = threadUniqueId
        self.loadRequest = loadRequest
        self.viewStateSnapshot = viewStateSnapshot
        self.spoilerReveal = spoilerReveal
        self.prevRenderState = prevRenderState
        self.messageMapping = messageMapping
    }

    func loadPromise() -> Promise<CVUpdate> {

        let threadUniqueId = self.threadUniqueId
        let loadRequest = self.loadRequest
        let viewStateSnapshot = self.viewStateSnapshot
        let spoilerReveal = self.spoilerReveal
        let prevRenderState = self.prevRenderState
        let messageMapping = self.messageMapping

        Logger.verbose("LoadType: \(loadRequest.loadType): \(loadRequest.loadStartDateFormatted)")

        struct LoadState {
            let threadViewModel: ThreadViewModel
            let items: [CVRenderItem]
            let threadInteractionCount: UInt
        }

        return firstly(on: CVUtils.workQueue(isInitialLoad: loadRequest.isInitialLoad)) { () -> CVUpdate in
            // To ensure coherency, the entire load should be done with a single transaction.
            let loadState: LoadState = try Self.databaseStorage.read { transaction in

                self.benchSteps.step("start")
                let loadThreadViewModel = { () -> ThreadViewModel in
                    guard let thread = TSThread.anyFetch(uniqueId: threadUniqueId, transaction: transaction) else {
                        // If thread has been deleted from the database, use last known model.
                        return prevRenderState.threadViewModel
                    }
                    return ThreadViewModel(thread: thread,
                                           forChatList: false,
                                           transaction: transaction)
                }
                let threadViewModel = loadThreadViewModel()

                let loadContext = CVLoadContext(
                    loadRequest: loadRequest,
                    threadViewModel: threadViewModel,
                    viewStateSnapshot: viewStateSnapshot,
                    spoilerReveal: spoilerReveal,
                    messageMapping: messageMapping,
                    prevRenderState: prevRenderState,
                    transaction: transaction
                )

                self.benchSteps.step("threadViewModel")

                if loadRequest.shouldClearOldestUnreadInteraction {
                    messageMapping.oldestUnreadInteraction = nil
                }

                // Don't cache in the reset() case.
                let canReuseInteractions = loadRequest.canReuseInteractionModels && !loadRequest.didReset
                var updatedInteractionIds = loadRequest.updatedInteractionIds
                let deletedInteractionIds: Set<String>? = loadRequest.didReset ? loadRequest.deletedInteractionIds : nil

                let didThreadDetailsChange: Bool = {
                    let prevThreadViewModel = prevRenderState.threadViewModel
                    guard let groupModel = threadViewModel.threadRecord.groupModelIfGroupThread else {
                        return false
                    }
                    guard let prevGroupModel = prevThreadViewModel.threadRecord.groupModelIfGroupThread else {
                        owsFailDebug("Missing groupModel.")
                        return false
                    }
                    let groupDescriptionDidChange = (groupModel as? TSGroupModelV2)?.descriptionText
                        != (prevGroupModel as? TSGroupModelV2)?.descriptionText
                    return (groupModel.groupName != prevGroupModel.groupName ||
                                groupDescriptionDidChange ||
                                groupModel.avatarHash != prevGroupModel.avatarHash ||
                                groupModel.groupMembership.fullMembers.count != prevGroupModel.groupMembership.fullMembers.count)
                }()

                // If the thread details did change, reload the thread details
                // item if one is in the load window.
                if didThreadDetailsChange,
                   let prevFirstRenderItem = prevRenderState.items.first,
                   prevFirstRenderItem.interactionType == .threadDetails {
                    updatedInteractionIds.insert(prevFirstRenderItem.interactionUniqueId)
                }

                var reusableInteractions = [String: TSInteraction]()
                if canReuseInteractions {
                    for renderItem in prevRenderState.items {
                        let interaction = renderItem.interaction
                        let interactionId = interaction.uniqueId
                        if !updatedInteractionIds.contains(interactionId) {
                            reusableInteractions[interactionId] = interaction
                        }
                    }
                }

                loadRequest.logLoadEvent("Before messageMapping")

                do {
                    switch loadRequest.loadType {
                    case .loadInitialMapping(let focusMessageIdOnOpen, _):
                        owsAssertDebug(reusableInteractions.isEmpty)
                        try messageMapping.loadInitialMessagePage(focusMessageId: focusMessageIdOnOpen,
                                                                  reusableInteractions: [:],
                                                                  deletedInteractionIds: [],
                                                                  transaction: transaction)
                    case .loadSameLocation:
                        try messageMapping.loadSameLocation(reusableInteractions: reusableInteractions,
                                                            deletedInteractionIds: deletedInteractionIds,
                                                            transaction: transaction)
                    case .loadOlder:
                        try messageMapping.loadOlderMessagePage(reusableInteractions: reusableInteractions,
                                                                deletedInteractionIds: deletedInteractionIds,
                                                                transaction: transaction)
                    case .loadNewer:
                        try messageMapping.loadNewerMessagePage(reusableInteractions: reusableInteractions,
                                                                deletedInteractionIds: deletedInteractionIds,
                                                                transaction: transaction)
                    case .loadNewest:
                        try messageMapping.loadNewestMessagePage(reusableInteractions: reusableInteractions,
                                                                 deletedInteractionIds: deletedInteractionIds,
                                                                 transaction: transaction)
                    case .loadPageAroundInteraction(let interactionId, _):
                        try messageMapping.loadMessagePage(aroundInteractionId: interactionId,
                                                           reusableInteractions: reusableInteractions,
                                                           deletedInteractionIds: deletedInteractionIds,
                                                           transaction: transaction)
                    }
                } catch {
                    owsFailDebug("Error: \(error)")
                    // Fail over to try to load newest.
                    try messageMapping.loadNewestMessagePage(reusableInteractions: reusableInteractions,
                                                             deletedInteractionIds: deletedInteractionIds,
                                                             transaction: transaction)
                }

                loadRequest.logLoadEvent("After messageMapping")
                self.benchSteps.step("messageMapping")

                let thread = threadViewModel.threadRecord
                let threadInteractionCount = thread.numberOfInteractions(
                    with: messageMapping.storyReplyQueryMode,
                    transaction: transaction)

                self.benchSteps.step("threadInteractionCount")

                loadRequest.logLoadEvent("Before buildRenderItems")

                let items: [CVRenderItem] = self.buildRenderItems(loadContext: loadContext,
                                                                  updatedInteractionIds: updatedInteractionIds)

                loadRequest.logLoadEvent("After buildRenderItems")

                self.benchSteps.step("buildRenderItems")

                let loadState = LoadState(threadViewModel: threadViewModel,
                                          items: items,
                                          threadInteractionCount: threadInteractionCount)

                loadRequest.logLoadEvent("After LoadState")

                return loadState
            }

            let items = loadState.items
            let threadViewModel = loadState.threadViewModel
            let renderState = CVRenderState(threadViewModel: threadViewModel,
                                            prevThreadViewModel: prevRenderState.threadViewModel,
                                            items: items,
                                            canLoadOlderItems: messageMapping.canLoadOlder,
                                            canLoadNewerItems: messageMapping.canLoadNewer,
                                            viewStateSnapshot: viewStateSnapshot,
                                            loadType: loadRequest.loadType)

            loadRequest.logLoadEvent("After renderState")

            self.benchSteps.step("build render state")

            let threadInteractionCount = loadState.threadInteractionCount
            let update = CVUpdate.build(renderState: renderState,
                                        prevRenderState: prevRenderState,
                                        loadRequest: loadRequest,
                                        threadInteractionCount: threadInteractionCount)

            loadRequest.logLoadEvent("After update built")

            self.benchSteps.step("build render update")

            self.benchSteps.logAll()

            return update
        }
    }

    // MARK: -

    private func buildRenderItems(loadContext: CVLoadContext,
                                  updatedInteractionIds: Set<String>) -> [CVRenderItem] {

        let conversationStyle = loadContext.conversationStyle

        // Don't cache in the reset() case.
        let canReuseState = (loadRequest.canReuseComponentStates &&
                                conversationStyle.isEqualForCellRendering(prevRenderState.conversationStyle))

        var itemModelBuilder = CVItemModelBuilder(loadContext: loadContext)

        // CVComponentStates are loaded from the database; these loads
        // can be expensive. Therefore we want to reuse them _unless_:
        //
        // * The corresponding interaction was updated.
        // * We're do a "reset" reload where we deliberately reload everything, e.g.
        //   in response to an error or a cross-process write, etc.
        if canReuseState {
            itemModelBuilder.reuseComponentStates(prevRenderState: prevRenderState,
                                                  updatedInteractionIds: updatedInteractionIds)
        }
        let itemModels: [CVItemModel] = itemModelBuilder.buildItems()

        var renderItems = [CVRenderItem]()
        for itemModel in itemModels {
            guard let renderItem = buildRenderItem(itemBuildingContext: loadContext,
                                                   itemModel: itemModel) else {
                continue
            }
            renderItems.append(renderItem)
        }

        return renderItems
    }

    private func buildRenderItem(itemBuildingContext: CVItemBuildingContext,
                                 itemModel: CVItemModel) -> CVRenderItem? {
        Self.buildRenderItem(itemBuildingContext: itemBuildingContext,
                             itemModel: itemModel)
    }

    #if DEBUG

    @objc
    public static func debugui_buildStandaloneRenderItem(
        interaction: TSInteraction,
        thread: TSThread,
        threadAssociatedData: ThreadAssociatedData,
        containerView: UIView,
        transaction: SDSAnyReadTransaction
    ) -> CVRenderItem? {
        buildStandaloneRenderItem(
            interaction: interaction,
            thread: thread,
            threadAssociatedData: threadAssociatedData,
            containerView: containerView,
            spoilerReveal: SpoilerRevealState(),
            transaction: transaction
        )
    }

    #endif

    public static func buildStandaloneRenderItem(
        interaction: TSInteraction,
        thread: TSThread,
        threadAssociatedData: ThreadAssociatedData,
        containerView: UIView,
        spoilerReveal: SpoilerRevealState,
        transaction: SDSAnyReadTransaction
    ) -> CVRenderItem? {
        let chatColor = ChatColors.chatColorForRendering(thread: thread, transaction: transaction)
        let conversationStyle = ConversationStyle(type: .`default`,
                                                  thread: thread,
                                                  viewWidth: containerView.width,
                                                  hasWallpaper: false,
                                                  isWallpaperPhoto: false,
                                                  chatColor: chatColor)
        let coreState = CVCoreState(conversationStyle: conversationStyle,
                                    mediaCache: CVMediaCache())
        return CVLoader.buildStandaloneRenderItem(
            interaction: interaction,
            thread: thread,
            threadAssociatedData: threadAssociatedData,
            coreState: coreState,
            spoilerReveal: spoilerReveal,
            transaction: transaction
        )
    }

    public static func buildStandaloneRenderItem(
        interaction: TSInteraction,
        thread: TSThread,
        threadAssociatedData: ThreadAssociatedData,
        conversationStyle: ConversationStyle,
        spoilerReveal: SpoilerRevealState,
        transaction: SDSAnyReadTransaction
    ) -> CVRenderItem? {
        let coreState = CVCoreState(
            conversationStyle: conversationStyle,
            mediaCache: CVMediaCache()
        )
        return CVLoader.buildStandaloneRenderItem(
            interaction: interaction,
            thread: thread,
            threadAssociatedData: threadAssociatedData,
            coreState: coreState,
            spoilerReveal: spoilerReveal,
            transaction: transaction
        )
    }

    private static func buildStandaloneRenderItem(
        interaction: TSInteraction,
        thread: TSThread,
        threadAssociatedData: ThreadAssociatedData,
        coreState: CVCoreState,
        spoilerReveal: SpoilerRevealState,
        transaction: SDSAnyReadTransaction
    ) -> CVRenderItem? {
        AssertIsOnMainThread()

        let threadViewModel = ThreadViewModel(thread: thread,
                                              forChatList: false,
                                              transaction: transaction)
        let viewStateSnapshot = CVViewStateSnapshot.mockSnapshotForStandaloneItems(
            coreState: coreState,
            spoilerReveal: spoilerReveal
        )
        let avatarBuilder = CVAvatarBuilder(transaction: transaction)
        let itemBuildingContext = CVItemBuildingContextImpl(
            threadViewModel: threadViewModel,
            viewStateSnapshot: viewStateSnapshot,
            transaction: transaction,
            avatarBuilder: avatarBuilder,
            spoilerReveal: spoilerReveal
        )
        guard let itemModel = CVItemModelBuilder.buildStandaloneItem(interaction: interaction,
                                                                     thread: thread,
                                                                     threadAssociatedData: threadAssociatedData,
                                                                     threadViewModel: threadViewModel,
                                                                     itemBuildingContext: itemBuildingContext,
                                                                     transaction: transaction) else {
            owsFailDebug("Couldn't build item model.")
            return nil
        }
        return Self.buildRenderItem(itemBuildingContext: itemBuildingContext,
                                    itemModel: itemModel)
    }

    public static func buildStandaloneComponentState(
        interaction: TSInteraction,
        spoilerReveal: SpoilerRevealState,
        transaction: SDSAnyReadTransaction
    ) -> CVComponentState? {
        AssertIsOnMainThread()

        let thread = interaction.thread(transaction: transaction)
        let chatColor = ChatColors.chatColorForRendering(thread: thread, transaction: transaction)
        let mockViewWidth: CGFloat = 800
        let conversationStyle = ConversationStyle(type: .`default`,
                                                  thread: thread,
                                                  viewWidth: mockViewWidth,
                                                  hasWallpaper: false,
                                                  isWallpaperPhoto: false,
                                                  chatColor: chatColor)
        let coreState = CVCoreState(conversationStyle: conversationStyle,
                                    mediaCache: CVMediaCache())
        let threadViewModel = ThreadViewModel(thread: thread,
                                              forChatList: false,
                                              transaction: transaction)
        let viewStateSnapshot = CVViewStateSnapshot.mockSnapshotForStandaloneItems(
            coreState: coreState,
            spoilerReveal: spoilerReveal
        )
        let avatarBuilder = CVAvatarBuilder(transaction: transaction)
        let itemBuildingContext = CVItemBuildingContextImpl(
            threadViewModel: threadViewModel,
            viewStateSnapshot: viewStateSnapshot,
            transaction: transaction,
            avatarBuilder: avatarBuilder,
            spoilerReveal: spoilerReveal
        )
        do {
            return try CVComponentState.build(interaction: interaction,
                                              itemBuildingContext: itemBuildingContext)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private static func buildRenderItem(itemBuildingContext: CVItemBuildingContext,
                                        itemModel: CVItemModel) -> CVRenderItem? {

        let conversationStyle = itemBuildingContext.conversationStyle

        let rootComponent: CVRootComponent
        switch itemModel.messageCellType {
        case .dateHeader:
            guard let dateHeaderState = itemModel.itemViewState.dateHeaderState else {
                owsFailDebug("Missing dateHeader.")
                return nil
            }
            rootComponent = CVComponentDateHeader(itemModel: itemModel,
                                                  dateHeaderState: dateHeaderState)
        case .unreadIndicator:
            rootComponent = CVComponentUnreadIndicator(itemModel: itemModel)
        case .threadDetails:
            guard let threadDetails = itemModel.componentState.threadDetails else {
                owsFailDebug("Missing threadDetails.")
                return nil
            }
            rootComponent = CVComponentThreadDetails(itemModel: itemModel, threadDetails: threadDetails)
        case .unknownThreadWarning:
            guard let unknownThreadWarning = itemModel.componentState.unknownThreadWarning else {
                owsFailDebug("Missing unknownThreadWarning.")
                return nil
            }
            rootComponent = CVComponentSystemMessage(itemModel: itemModel,
                                                     systemMessage: unknownThreadWarning)
        case .defaultDisappearingMessageTimer:
            guard let defaultDisappearingMessageTimer = itemModel.componentState.defaultDisappearingMessageTimer else {
                owsFailDebug("Missing unknownThreadWarning.")
                return nil
            }
            rootComponent = CVComponentSystemMessage(itemModel: itemModel,
                                                     systemMessage: defaultDisappearingMessageTimer)
        case .textOnlyMessage, .audio, .genericAttachment, .contactShare,
                .bodyMedia, .viewOnce, .stickerMessage, .quoteOnlyMessage,
                .giftBadge:
            rootComponent = CVComponentMessage(itemModel: itemModel)
        case .typingIndicator:
            guard let typingIndicator = itemModel.componentState.typingIndicator else {
                owsFailDebug("Missing typingIndicator.")
                return nil
            }
            rootComponent = CVComponentTypingIndicator(itemModel: itemModel,
                                                       typingIndicator: typingIndicator)
        case .systemMessage:
            guard let systemMessage = itemModel.componentState.systemMessage else {
                owsFailDebug("Missing systemMessage.")
                return nil
            }
            rootComponent = CVComponentSystemMessage(itemModel: itemModel, systemMessage: systemMessage)
        case .unknown:
            Logger.warn("Discarding item: \(itemModel.messageCellType).")
            return nil
        }

        let cellMeasurement = buildCellMeasurement(rootComponent: rootComponent,
                                                   conversationStyle: conversationStyle)

        return CVRenderItem(itemModel: itemModel,
                            rootComponent: rootComponent,
                            cellMeasurement: cellMeasurement)
    }

    private static func buildEmptyCellMeasurement() -> CVCellMeasurement {
        CVCellMeasurement.Builder().build()
    }

    private static func buildCellMeasurement(rootComponent: CVRootComponent,
                                             conversationStyle: ConversationStyle) -> CVCellMeasurement {
        let measurementBuilder = CVCellMeasurement.Builder()
        measurementBuilder.cellSize = rootComponent.measure(maxWidth: conversationStyle.viewWidth,
                                                            measurementBuilder: measurementBuilder)
        let cellMeasurement = measurementBuilder.build()
        owsAssertDebug(cellMeasurement.cellSize.width <= conversationStyle.viewWidth)
        return cellMeasurement
    }
}
