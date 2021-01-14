//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// CVItemViewState represents the transient, un-persisted values
// that may affect item appearance.
//
// Compare with CVComponentState which represents the persisted values
// that may affect item appearance.
//
// CVItemViewState might be affected by adjacent items, profile changes,
// the passage of time, etc.
public struct CVItemViewState: Equatable {
    let shouldShowSenderAvatar: Bool
    let senderName: NSAttributedString?
    let accessibilityAuthorName: String?
    let shouldHideFooter: Bool
    let isFirstInCluster: Bool
    let isLastInCluster: Bool
    let shouldCollapseSystemMessageAction: Bool

    // Some components have transient state.
    let footerState: CVComponentFooter.State?
    let dateHeaderState: CVComponentDateHeader.State?
    let bodyTextState: CVComponentBodyText.State?

    let isShowingSelectionUI: Bool

    public class Builder {
        var shouldShowSenderAvatar = false
        var senderName: NSAttributedString?
        var accessibilityAuthorName: String?
        var shouldHideFooter = false
        var isFirstInCluster = false
        var isLastInCluster = false
        var shouldCollapseSystemMessageAction = false
        var footerState: CVComponentFooter.State?
        var dateHeaderState: CVComponentDateHeader.State?
        var bodyTextState: CVComponentBodyText.State?
        var isShowingSelectionUI = false

        func build() -> CVItemViewState {
            CVItemViewState(shouldShowSenderAvatar: shouldShowSenderAvatar,
                            senderName: senderName,
                            accessibilityAuthorName: accessibilityAuthorName,
                            shouldHideFooter: shouldHideFooter,
                            isFirstInCluster: isFirstInCluster,
                            isLastInCluster: isLastInCluster,
                            shouldCollapseSystemMessageAction: shouldCollapseSystemMessageAction,
                            footerState: footerState,
                            dateHeaderState: dateHeaderState,
                            bodyTextState: bodyTextState,
                            isShowingSelectionUI: isShowingSelectionUI)
        }
    }
}

// MARK: -

struct CVItemModelBuilder: CVItemBuilding {

    // MARK: - Dependencies

    private static var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private static var profileManager: OWSProfileManager {
        return .shared()
    }

    // MARK: -

    let itemBuildingContext: CVItemBuildingContext
    let messageMapping: CVMessageMapping

    // MARK: -

    private var shouldShowDateOnNextViewItem = true
    private var previousItemTimestamp: UInt64 = 0

    private var items = [ItemBuilder]()
    private var previousItem: ItemBuilder? {
        items.last
    }

    init(loadContext: CVLoadContext) {
        self.itemBuildingContext = loadContext
        self.messageMapping = loadContext.messageMapping
    }

    // TODO: How should we handle failed stickers?
    // TODO: Do we need a new equivalent of clearNeedsUpdate?
    mutating func buildItems() -> [CVItemModel] {

        // Contact Offers / Thread Details are the first item in the thread
        if messageMapping.shouldShowThreadDetails {
            Logger.debug("adding thread details")

            // The thread details should have a stable timestamp.
            let threadDetailsTimestamp: UInt64
            if let firstInteraction = messageMapping.loadedInteractions.first {
                threadDetailsTimestamp = max(1, firstInteraction.timestamp) - 1
            } else {
                threadDetailsTimestamp = 1
            }
            let threadDetails = ThreadDetailsInteraction(thread: thread,
                                                         timestamp: threadDetailsTimestamp)
            let item = addItem(interaction: threadDetails)
            owsAssertDebug(item != nil)
        }

        var interactionIds = Set<String>()
        for interaction in messageMapping.loadedInteractions {
            guard !interactionIds.contains(interaction.uniqueId) else {
                owsFailDebug("Duplicate interaction(1): \(interaction.uniqueId)")
                continue
            }
            interactionIds.insert(interaction.uniqueId)

            let item = addItem(interaction: interaction)
            owsAssertDebug(item != nil)
        }

        // TODO: We need to handle unsavedOutgoingMessages, ie. optimistically
        //       inserting messages into the "view model" so that sent messages
        //       appear as quickly as possible.
        //
        //            if (self.unsavedOutgoingMessages.count > 0) {
        //                for (TSOutgoingMessage *outgoingMessage in self.unsavedOutgoingMessages) {
        //                    if ([interactionIds containsObject:outgoingMessage.uniqueId]) {
        //                        owsFailDebug("Duplicate interaction(2): %@", outgoingMessage.uniqueId);
        //                        continue;
        //                    }
        //                    tryToAddViewItemForInteraction(outgoingMessage);
        //                    [interactionIds addObject:outgoingMessage.uniqueId];
        //                }
        //            }

        if let typingIndicatorsSender = viewStateSnapshot.typingIndicatorsSender {
            let interaction = TypingIndicatorInteraction(thread: thread,
                                                         timestamp: NSDate.ows_millisecondTimeStamp(),
                                                         address: typingIndicatorsSender)
            let item = addItem(interaction: interaction)
            owsAssertDebug(item != nil)
        }

        // Update the properties of the view items.
        //
        // NOTE: This logic uses the break properties which are set in the previous pass.
        for (index, item) in items.enumerated() {
            let previousItem: ItemBuilder? = items[safe: index - 1]
            let nextItem: ItemBuilder? = items[safe: index + 1]

            Self.configureItemViewState(item: item,
                                        previousItem: previousItem,
                                        nextItem: nextItem,
                                        thread: thread,
                                        viewStateSnapshot: viewStateSnapshot,
                                        transaction: transaction)
        }

        return items.map { (itemBuilder: ItemBuilder) in
            itemBuilder.build(coreState: viewStateSnapshot.coreState)
        }
    }

    public static func buildStandaloneItem(interaction: TSInteraction,
                                           thread: TSThread,
                                           itemBuildingContext: CVItemBuildingContext,
                                           transaction: SDSAnyReadTransaction) -> CVItemModel? {
        AssertIsOnMainThread()

        let viewStateSnapshot = itemBuildingContext.viewStateSnapshot

        guard let itemBuilder = Self.itemBuilder(forInteraction: interaction,
                                                 thread: thread,
                                                 itemBuildingContext: itemBuildingContext,
                                                 componentStateCache: ComponentStateCache()) else {
            owsFailDebug("Could not create itemBuilder.")
            return nil
        }

        configureItemViewState(item: itemBuilder,
                               previousItem: nil,
                               nextItem: nil,
                               thread: thread,
                               viewStateSnapshot: viewStateSnapshot,
                               transaction: transaction)

        return itemBuilder.build(coreState: viewStateSnapshot.coreState)
    }

    private static func configureItemViewState(item: ItemBuilder,
                                               previousItem: ItemBuilder?,
                                               nextItem: ItemBuilder?,
                                               thread: TSThread,
                                               viewStateSnapshot: CVViewStateSnapshot,
                                               transaction: SDSAnyReadTransaction) {
        let itemViewState = item.itemViewState
        itemViewState.shouldShowSenderAvatar = false
        itemViewState.shouldHideFooter = false
        itemViewState.isFirstInCluster = true
        itemViewState.isLastInCluster = true

        let interaction = item.interaction
        let timestampText = DateUtil.formatTimestampShort(interaction.timestamp)

        let hasTapForMore: Bool = {
            guard let bodyText = item.componentState.bodyText,
                  let displayableText = bodyText.displayableText else {
                return false
            }
            guard displayableText.isTextTruncated else {
                return false
            }
            let interactionId = item.interaction.uniqueId
            let isTruncatedTextVisible = viewStateSnapshot.textExpansion.isTextExpanded(interactionId: interactionId)
            return !isTruncatedTextVisible
        }()
        itemViewState.footerState = CVComponentFooter.buildState(interaction: interaction,
                                                                 hasTapForMore: hasTapForMore)

        if interaction.interactionType() == .dateHeader {
            itemViewState.dateHeaderState = CVComponentDateHeader.buildState(interaction: interaction)
        }
        if let bodyText = item.componentState.bodyText {
            itemViewState.bodyTextState = CVComponentBodyText.buildState(interaction: interaction,
                                                                         bodyText: bodyText,
                                                                         viewStateSnapshot: viewStateSnapshot,
                                                                         hasTapForMore: hasTapForMore)
        }

        itemViewState.isShowingSelectionUI = viewStateSnapshot.isShowingSelectionUI

        if let outgoingMessage = interaction as? TSOutgoingMessage {
            let receiptStatus = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: outgoingMessage)
            let isDisappearingMessage = outgoingMessage.hasPerConversationExpiration
            itemViewState.accessibilityAuthorName = NSLocalizedString("ACCESSIBILITY_LABEL_SENDER_SELF",
                                                                      comment: "Accessibility label for messages sent by you.")

            if let nextItem = nextItem,
               let nextOutgoingMessage = nextItem.interaction as? TSOutgoingMessage {
                let nextReceiptStatus = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: nextOutgoingMessage)
                let nextTimestampText = DateUtil.formatTimestampShort(nextOutgoingMessage.timestamp)

                // We can skip the "outgoing message status" footer if the next message
                // has the same footer and no "date break" separates us...
                // ...but always show the "sending" and "failed to send" statuses...
                // ...and always show the "disappearing messages" animation...
                // ...and always show the "tap to read more" footer.
                itemViewState.shouldHideFooter = (timestampText == nextTimestampText &&
                                                    receiptStatus == nextReceiptStatus &&
                                                    outgoingMessage.messageState != .failed &&
                                                    outgoingMessage.messageState != .sending &&
                                                    !isDisappearingMessage &&
                                                    !hasTapForMore)
            }

            // clustering
            if let previousItem = previousItem {
                itemViewState.isFirstInCluster = previousItem.interactionType != .outgoingMessage
            } else {
                itemViewState.isFirstInCluster = true
            }

            if let nextItem = nextItem {
                itemViewState.isLastInCluster = nextItem.interactionType != .outgoingMessage
            } else {
                itemViewState.isLastInCluster = true
            }
        } else if let incomingMessage = interaction as? TSIncomingMessage {
            let incomingSenderAddress: SignalServiceAddress = incomingMessage.authorAddress
            owsAssertDebug(incomingSenderAddress.isValid)
            let isDisappearingMessage = incomingMessage.hasPerConversationExpiration
            let authorName = contactsManager.displayName(for: incomingSenderAddress,
                                                         transaction: transaction)
            itemViewState.accessibilityAuthorName = authorName

            if let nextItem = nextItem,
               let nextIncomingMessage = nextItem.interaction as? TSIncomingMessage {
                let nextIncomingSenderAddress: SignalServiceAddress = nextIncomingMessage.authorAddress
                owsAssertDebug(nextIncomingMessage.authorAddress.isValid)

                let nextTimestampText = DateUtil.formatTimestampShort(nextIncomingMessage.timestamp)

                // We can skip the "incoming message status" footer in a cluster if the next message
                // has the same footer and no "date break" separates us...
                // ...but always show the "disappearing messages" animation...
                // ...and always show the "tap to read more" footer.
                itemViewState.shouldHideFooter = (timestampText == nextTimestampText &&
                                                    incomingSenderAddress == nextIncomingSenderAddress &&
                                                    !isDisappearingMessage &&
                                                    !hasTapForMore)
            }

            // clustering

            if let previousItem = previousItem,
               let previousIncomingMessage = previousItem.interaction as? TSIncomingMessage {
                itemViewState.isFirstInCluster = incomingSenderAddress != previousIncomingMessage.authorAddress
            } else {
                itemViewState.isFirstInCluster = true
            }

            if let nextItem = nextItem,
               let nextIncomingMessage = nextItem.interaction as? TSIncomingMessage {
                itemViewState.isLastInCluster = incomingSenderAddress != nextIncomingMessage.authorAddress
            } else {
                itemViewState.isLastInCluster = true
            }

            if thread.isGroupThread {
                // Show the sender name for incoming group messages unless
                // the previous message has the same sender name and
                // no "date break" separates us.
                var shouldShowSenderName = true
                if let previousItem = previousItem,
                   let previousIncomingMessage = previousItem.interaction as? TSIncomingMessage {
                    let previousIncomingSenderAddress = previousIncomingMessage.authorAddress
                    owsAssertDebug(previousIncomingSenderAddress.isValid)

                    shouldShowSenderName = incomingSenderAddress != previousIncomingSenderAddress
                }
                if shouldShowSenderName {
                    itemViewState.senderName = NSAttributedString(string: authorName)
                }

                // Show the sender avatar for incoming group messages unless
                // the next message has the same sender avatar and
                // no "date break" separates us.
                itemViewState.shouldShowSenderAvatar = true
                if let nextItem = nextItem,
                   let nextIncomingMessage = nextItem.interaction as? TSIncomingMessage {
                    let nextIncomingSenderAddress: SignalServiceAddress = nextIncomingMessage.authorAddress
                    itemViewState.shouldShowSenderAvatar = incomingSenderAddress != nextIncomingSenderAddress
                }
            }
        }

        let collapseCutoffTimestamp = NSDate.ows_millisecondsSince1970(for: viewStateSnapshot.collapseCutoffDate)
        if interaction.receivedAtTimestamp > collapseCutoffTimestamp {
            itemViewState.shouldHideFooter = false
        }
    }

    private mutating func addDateHeaderViewItemIfNecessary(item: ItemBuilder) {
        let itemTimestamp = item.interaction.timestamp
        owsAssertDebug(itemTimestamp > 0)

        var shouldShowDate = false
        if previousItemTimestamp == 0 {
            // Only show for the first item if the date is not today
            shouldShowDateOnNextViewItem = !DateUtil.dateIsToday(NSDate.ows_date(withMillisecondsSince1970: itemTimestamp))
        } else if !DateUtil.isSameDay(withTimestamp: itemTimestamp, timestamp: previousItemTimestamp) {
            shouldShowDateOnNextViewItem = true
        }

        if shouldShowDateOnNextViewItem && item.canShowDate {
            shouldShowDate = true
            shouldShowDateOnNextViewItem = false
        }

        if shouldShowDate {
            let interaction = DateHeaderInteraction(thread: thread, timestamp: itemTimestamp)
            let componentState = CVComponentState.buildDateHeader(interaction: interaction,
                                                                  itemBuildingContext: itemBuildingContext)
            let item = ItemBuilder(interaction: interaction,
                                   thread: thread,
                                   componentState: componentState)
            items.append(item)
        }

        previousItemTimestamp = itemTimestamp
    }

    var hasPlacedUnreadIndicator = false

    private mutating func addUnreadHeaderViewItemIfNecessary(item: ItemBuilder) {
        let itemTimestamp = item.interaction.timestamp
        owsAssertDebug(itemTimestamp > 0)

        if !hasPlacedUnreadIndicator,
           !viewStateSnapshot.hasClearedUnreadMessagesIndicator,
           let oldestUnreadInteraction = messageMapping.oldestUnreadInteraction,
           oldestUnreadInteraction.sortId <= item.interaction.sortId {

            hasPlacedUnreadIndicator = true
            let interaction = UnreadIndicatorInteraction(thread: thread,
                                                         timestamp: itemTimestamp,
                                                         receivedAtTimestamp: item.interaction.receivedAtTimestamp)
            let componentState = CVComponentState.buildUnreadIndicator(interaction: interaction,
                                                                       itemBuildingContext: itemBuildingContext)
            let item = ItemBuilder(interaction: interaction,
                                   thread: thread,
                                   componentState: componentState)
            items.append(item)
        }
    }

    private class ComponentStateCache {
        var cache = [String: CVComponentState]()

        func add(interactionId: String, componentState: CVComponentState) {
            cache[interactionId] = componentState
        }

        func get(interactionId: String) -> CVComponentState? {
            cache[interactionId]
        }
    }
    private var componentStateCache = ComponentStateCache()

    mutating func reuseComponentStates(prevRenderState: CVRenderState,
                                       updatedInteractionIds: Set<String>) {

        for renderItem in prevRenderState.items {
            guard !updatedInteractionIds.contains(renderItem.interactionUniqueId) else {
                continue
            }
            componentStateCache.add(interactionId: renderItem.interactionUniqueId,
                                    componentState: renderItem.rootComponent.componentState)
        }
    }

    private static func buildComponentState(interaction: TSInteraction,
                                            itemBuildingContext: CVItemBuildingContext,
                                            componentStateCache: ComponentStateCache) throws -> CVComponentState {
        if let componentState = componentStateCache.get(interactionId: interaction.uniqueId) {
            // CVComponentState is immutable and safe to re-use without copying. It's currently a struct.
            return componentState
        }
        return try CVComponentState.build(interaction: interaction,
                                          itemBuildingContext: itemBuildingContext)
    }

    private mutating func addItem(interaction: TSInteraction) -> ItemBuilder? {
        guard let item = Self.itemBuilder(forInteraction: interaction,
                                          thread: thread,
                                          itemBuildingContext: itemBuildingContext,
                                          componentStateCache: componentStateCache) else {
            return nil
        }

        // Insert dynamic header item(s) before this item if necessary.
        addDateHeaderViewItemIfNecessary(item: item)
        addUnreadHeaderViewItemIfNecessary(item: item)

        if let previousItem = previousItem {
            configureAdjacent(item: item,
                              previousItem: previousItem,
                              viewStateSnapshot: viewStateSnapshot)
        }

        // Hide "call" buttons if there is an active call in another thread.
        if item.interactionType == .call {
            let threadId = thread.uniqueId
            let activeCallThreadId = viewStateSnapshot.currentCallThreadId
            let isAnotherThreadInCall = (activeCallThreadId != nil && threadId != activeCallThreadId)
            if isAnotherThreadInCall {
                item.itemViewState.shouldCollapseSystemMessageAction = true
            }
        }

        items.append(item)

        return item
    }

    private static func itemBuilder(forInteraction interaction: TSInteraction,
                                    thread: TSThread,
                                    itemBuildingContext: CVItemBuildingContext,
                                    componentStateCache: ComponentStateCache) -> ItemBuilder? {
        let componentState: CVComponentState
        do {
            componentState = try buildComponentState(interaction: interaction,
                                                     itemBuildingContext: itemBuildingContext,
                                                     componentStateCache: componentStateCache)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }

        return ItemBuilder(interaction: interaction,
                           thread: thread,
                           componentState: componentState)
    }

    private func configureAdjacent(item: ItemBuilder,
                                   previousItem: ItemBuilder,
                                   viewStateSnapshot: CVViewStateSnapshot) {
        let interaction = item.interaction
        guard previousItem.interactionType == item.interactionType else {
            return
        }

        switch item.interactionType {
        case .error:
            guard let errorMessage = interaction as? TSErrorMessage,
                  let previousErrorMessage = previousItem.interaction as? TSErrorMessage else {
                owsFailDebug("Invalid interactions.")
                return
            }
            if errorMessage.errorType == .nonBlockingIdentityChange {
                return
            }
            previousItem.itemViewState.shouldCollapseSystemMessageAction
                = previousErrorMessage.errorType == errorMessage.errorType
        case .info:
            guard let infoMessage = interaction as? TSInfoMessage,
                  let previousInfoMessage = previousItem.interaction as? TSInfoMessage else {
                owsFailDebug("Invalid interactions.")
                return
            }
            if infoMessage.messageType == .verificationStateChange {
                return
            }
            previousItem.itemViewState.shouldCollapseSystemMessageAction
                = (previousInfoMessage.messageType == infoMessage.messageType
                    && !previousInfoMessage.isGroupMigrationMessage
                    && !previousInfoMessage.isGroupWasJustCreatedByLocalUserMessage)
        case .call:
            previousItem.itemViewState.shouldCollapseSystemMessageAction = true
        default:
            break
        }
    }
}

// MARK: -

fileprivate extension CVMessageMapping {
    var shouldShowThreadDetails: Bool {
        !canLoadOlder
    }
}

// MARK: -

private class ItemBuilder {
    let interaction: TSInteraction
    let thread: TSThread
    let componentState: CVComponentState
    var itemViewState = CVItemViewState.Builder()

    required init(interaction: TSInteraction,
                  thread: TSThread,
                  componentState: CVComponentState) {
        self.interaction = interaction
        self.thread = thread
        self.componentState = componentState
    }

    func build(coreState: CVCoreState) -> CVItemModel {
        CVItemModel(interaction: interaction,
                    thread: thread,
                    componentState: componentState,
                    itemViewState: itemViewState.build(),
                    coreState: coreState)
    }

    var interactionType: OWSInteractionType {
        interaction.interactionType()
    }

    var canShowDate: Bool {
        switch interaction.interactionType() {
        case .unknown, .typingIndicator, .threadDetails, .dateHeader:
            return false
        case .info:
            guard let infoMessage = interaction as? TSInfoMessage else {
                owsFailDebug("Invalid interaction.")
                return false
            }
            // Only show the date for non-synced thread messages;
            return infoMessage.messageType != .syncedThread
        case .unreadIndicator, .incomingMessage, .outgoingMessage, .error, .call:
            return true
        }
    }
}
