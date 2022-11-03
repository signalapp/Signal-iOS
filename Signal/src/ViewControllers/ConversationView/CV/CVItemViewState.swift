//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

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
    let accessibilityAuthorName: String?
    let shouldHideFooter: Bool
    let isFirstInCluster: Bool
    let isLastInCluster: Bool
    let shouldCollapseSystemMessageAction: Bool

    // Some components have transient state.
    let senderNameState: CVComponentState.SenderName?
    let footerState: CVComponentFooter.State?
    let dateHeaderState: CVComponentDateHeader.State?
    let bodyTextState: CVComponentBodyText.State?
    let giftBadgeState: CVComponentGiftBadge.ViewState?
    let nextAudioAttachment: AudioAttachment?
    let audioPlaybackRate: Float

    let uiMode: ConversationUIMode
    let previousUIMode: ConversationUIMode

    public var isShowingSelectionUI: Bool { uiMode.hasSelectionUI }
    public var wasShowingSelectionUI: Bool { previousUIMode.hasSelectionUI }

    public class Builder {
        var shouldShowSenderAvatar = false
        var accessibilityAuthorName: String?
        var shouldHideFooter = false
        var isFirstInCluster = false
        var isLastInCluster = false
        var shouldCollapseSystemMessageAction = false
        var senderNameState: CVComponentState.SenderName?
        var footerState: CVComponentFooter.State?
        var dateHeaderState: CVComponentDateHeader.State?
        var bodyTextState: CVComponentBodyText.State?
        var giftBadgeState: CVComponentGiftBadge.ViewState?
        var nextAudioAttachment: AudioAttachment?
        var audioPlaybackRate: Float = 1
        var uiMode: ConversationUIMode = .normal
        var previousUIMode: ConversationUIMode = .normal

        func build() -> CVItemViewState {
            CVItemViewState(shouldShowSenderAvatar: shouldShowSenderAvatar,
                            accessibilityAuthorName: accessibilityAuthorName,
                            shouldHideFooter: shouldHideFooter,
                            isFirstInCluster: isFirstInCluster,
                            isLastInCluster: isLastInCluster,
                            shouldCollapseSystemMessageAction: shouldCollapseSystemMessageAction,
                            senderNameState: senderNameState,
                            footerState: footerState,
                            dateHeaderState: dateHeaderState,
                            bodyTextState: bodyTextState,
                            giftBadgeState: giftBadgeState,
                            nextAudioAttachment: nextAudioAttachment,
                            audioPlaybackRate: audioPlaybackRate,
                            uiMode: uiMode,
                            previousUIMode: previousUIMode)
        }
    }
}

// MARK: -

struct CVItemModelBuilder: CVItemBuilding, Dependencies {

    let itemBuildingContext: CVItemBuildingContext
    let messageMapping: CVMessageMapping

    // MARK: -

    private var shouldShowDateOnNextViewItem = true
    private let todayDate = Date()
    private var previousDaysBeforeToday: Int?

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
                threadDetailsTimestamp = max(1, firstInteraction.timestamp) - 2
            } else {
                threadDetailsTimestamp = 1
            }
            let threadDetails = ThreadDetailsInteraction(thread: thread,
                                                         timestamp: threadDetailsTimestamp)
            let item = addItem(interaction: threadDetails)
            owsAssertDebug(item != nil)
        }

        // UnknownThreadWarning are the second item in the thread
        if messageMapping.shouldShowUnknownThreadWarning(thread: thread,
                                                         transaction: transaction) {
            Logger.debug("adding UnknownThreadWarning")

            // The "Unknown Thread Warning" should have a stable timestamp.
            let timestamp: UInt64
            if let firstInteraction = messageMapping.loadedInteractions.first {
                timestamp = max(1, firstInteraction.timestamp) - 1
            } else {
                timestamp = 2
            }
            let unknownThreadWarning = UnknownThreadWarningInteraction(thread: thread,
                                                                       timestamp: timestamp)
            let item = addItem(interaction: unknownThreadWarning)
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

        if messageMapping.shouldShowDefaultDisappearingMessageTimer(
            thread: thread,
            transaction: transaction
        ) {
            let interaction = DefaultDisappearingMessageTimerInteraction(
                thread: thread,
                timestamp: NSDate.ows_millisecondTimeStamp() - 1
            )
            let item = addItem(interaction: interaction)
            owsAssertDebug(item != nil)
        }

        if let typingIndicatorsSender = viewStateSnapshot.typingIndicatorsSender {
            let interaction = TypingIndicatorInteraction(thread: thread,
                                                         timestamp: NSDate.ows_millisecondTimeStamp(),
                                                         address: typingIndicatorsSender)
            let item = addItem(interaction: interaction)
            owsAssertDebug(item != nil)
        }

        let groupNameColors = ChatColors.groupNameColors(forThread: thread)
        let displayNameCache = DisplayNameCache()

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
                                        threadViewModel: threadViewModel,
                                        viewStateSnapshot: viewStateSnapshot,
                                        groupNameColors: groupNameColors,
                                        displayNameCache: displayNameCache,
                                        transaction: transaction)
        }

        return items.map { (itemBuilder: ItemBuilder) in
            itemBuilder.build(coreState: viewStateSnapshot.coreState)
        }
    }

    public static func buildStandaloneItem(interaction: TSInteraction,
                                           thread: TSThread,
                                           threadAssociatedData: ThreadAssociatedData,
                                           threadViewModel: ThreadViewModel,
                                           itemBuildingContext: CVItemBuildingContext,
                                           transaction: SDSAnyReadTransaction) -> CVItemModel? {
        AssertIsOnMainThread()

        let viewStateSnapshot = itemBuildingContext.viewStateSnapshot

        guard let itemBuilder = Self.itemBuilder(forInteraction: interaction,
                                                 thread: thread,
                                                 threadAssociatedData: threadAssociatedData,
                                                 itemBuildingContext: itemBuildingContext,
                                                 componentStateCache: ComponentStateCache()) else {
            owsFailDebug("Could not create itemBuilder.")
            return nil
        }

        let groupNameColors = ChatColors.groupNameColors(forThread: thread)
        let displayNameCache = DisplayNameCache()

        configureItemViewState(item: itemBuilder,
                               previousItem: nil,
                               nextItem: nil,
                               thread: thread,
                               threadViewModel: threadViewModel,
                               viewStateSnapshot: viewStateSnapshot,
                               groupNameColors: groupNameColors,
                               displayNameCache: displayNameCache,
                               transaction: transaction)

        return itemBuilder.build(coreState: viewStateSnapshot.coreState)
    }

    private static func configureItemViewState(item: ItemBuilder,
                                               previousItem: ItemBuilder?,
                                               nextItem: ItemBuilder?,
                                               thread: TSThread,
                                               threadViewModel: ThreadViewModel,
                                               viewStateSnapshot: CVViewStateSnapshot,
                                               groupNameColors: ChatColors.GroupNameColors,
                                               displayNameCache: DisplayNameCache,
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

        if let giftBadge = item.componentState.giftBadge {
            itemViewState.giftBadgeState = CVComponentGiftBadge.buildViewState(giftBadge)
        }

        itemViewState.audioPlaybackRate =  threadViewModel.associatedData.audioPlaybackRate

        if interaction.interactionType == .dateHeader {
            itemViewState.dateHeaderState = CVComponentDateHeader.buildState(interaction: interaction)
        }
        if let bodyText = item.componentState.bodyText {
            itemViewState.bodyTextState = CVComponentBodyText.buildState(interaction: interaction,
                                                                         bodyText: bodyText,
                                                                         viewStateSnapshot: viewStateSnapshot,
                                                                         hasTapForMore: hasTapForMore,
                                                                         hasPendingMessageRequest: threadViewModel.hasPendingMessageRequest)
        }
        itemViewState.uiMode = viewStateSnapshot.uiMode
        itemViewState.previousUIMode = viewStateSnapshot.previousUIMode

        func canClusterMessages(_ left: ItemBuilder, _ right: ItemBuilder) -> Bool {
            let leftTime = left.interaction.receivedAtTimestamp
            let rightTime = right.interaction.receivedAtTimestamp
            if rightTime < leftTime {
                // Ensure left was received first.
                return canClusterMessages(right, left)
            }
            if left.componentState.reactions != nil {
                // Don't cluster message if the earlier message has a reaction.
                return false
            }
            let maxClusterTimeDifferenceMs = UInt64(kMinuteInMs) * 3
            let elapsedMs = rightTime - leftTime
            return elapsedMs < maxClusterTimeDifferenceMs
        }

        if let outgoingMessage = interaction as? TSOutgoingMessage {
            let receiptStatus = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: outgoingMessage)
            let isDisappearingMessage = outgoingMessage.hasPerConversationExpiration
            itemViewState.accessibilityAuthorName = CommonStrings.you

            // clustering
            if let previousItem = previousItem,
               previousItem.interactionType == .outgoingMessage,
               canClusterMessages(previousItem, item) {
                itemViewState.isFirstInCluster = false
            } else {
                itemViewState.isFirstInCluster = true
            }

            if let nextItem = nextItem,
               let nextOutgoingMessage = nextItem.interaction as? TSOutgoingMessage,
               canClusterMessages(item, nextItem) {
                itemViewState.isLastInCluster = false

                // We can skip the "outgoing message status" footer if the next message
                // has the same footer and no "date break" separates us...
                // ...but always show the "sending" and "failed to send" statuses...
                // ...and always show the "disappearing messages" animation...
                // ...and always show the "tap to read more" footer.
                let nextReceiptStatus = MessageRecipientStatusUtils.recipientStatus(outgoingMessage: nextOutgoingMessage)
                let nextTimestampText = DateUtil.formatTimestampShort(nextOutgoingMessage.timestamp)
                itemViewState.shouldHideFooter = (timestampText == nextTimestampText &&
                                                    receiptStatus == nextReceiptStatus &&
                                                    outgoingMessage.messageState != .failed &&
                                                    outgoingMessage.messageState != .sending &&
                                                    outgoingMessage.messageState != .pending &&
                                                    !isDisappearingMessage &&
                                                    !hasTapForMore)
            } else {
                itemViewState.isLastInCluster = true
            }
        } else if let incomingMessage = interaction as? TSIncomingMessage {
            let incomingSenderAddress: SignalServiceAddress = incomingMessage.authorAddress
            owsAssertDebug(incomingSenderAddress.isValid)
            let isDisappearingMessage = incomingMessage.hasPerConversationExpiration

            // clustering

            if let previousItem = previousItem,
               let previousIncomingMessage = previousItem.interaction as? TSIncomingMessage,
               incomingSenderAddress == previousIncomingMessage.authorAddress,
               canClusterMessages(previousItem, item) {
                itemViewState.isFirstInCluster = false
            } else {
                itemViewState.isFirstInCluster = true
            }

            if let nextItem = nextItem,
               let nextIncomingMessage = nextItem.interaction as? TSIncomingMessage,
                incomingSenderAddress == nextIncomingMessage.authorAddress,
                canClusterMessages(item, nextItem) {
                itemViewState.isLastInCluster = false

                // We can skip the "incoming message status" footer in a cluster if the next message
                // has the same footer and no "date break" separates us...
                // ...but always show the "disappearing messages" animation...
                // ...and always show the "tap to read more" footer.
                let nextTimestampText = DateUtil.formatTimestampShort(nextIncomingMessage.timestamp)
                itemViewState.shouldHideFooter = (timestampText == nextTimestampText &&
                                                    !isDisappearingMessage &&
                                                    !hasTapForMore)
            } else {
                itemViewState.isLastInCluster = true
            }

            if thread.isGroupThread {
                // Show the sender name for incoming group messages unless
                // the previous message has the same sender name and
                // no "date break" separates us.
                var shouldShowSenderName = true
                let authorName = displayNameCache.displayName(address: incomingSenderAddress, transaction: transaction)
                itemViewState.accessibilityAuthorName = authorName

                if let previousItem = previousItem,
                   let previousIncomingMessage = previousItem.interaction as? TSIncomingMessage {
                    let previousIncomingSenderAddress = previousIncomingMessage.authorAddress
                    owsAssertDebug(previousIncomingSenderAddress.isValid)

                    shouldShowSenderName = incomingSenderAddress != previousIncomingSenderAddress
                }
                if shouldShowSenderName {
                    let senderName = NSAttributedString(string: authorName)
                    let senderNameColor = groupNameColors.color(for: incomingSenderAddress)
                    itemViewState.senderNameState = CVComponentState.SenderName(senderName: senderName,
                                                                                senderNameColor: senderNameColor)
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
            } else {
                // In a 1:1 thread, we can avoid cluttering up voiceover string with the recipient's
                // full name. Group thread's will continue to read off the full name.
                itemViewState.accessibilityAuthorName = displayNameCache.shortDisplayName(
                    address: incomingSenderAddress,
                    transaction: transaction
                )
            }

        } else if [.call, .info, .error].contains(interaction.interactionType) {
            // clustering

            if let previousItem = previousItem,
               interaction.interactionType == previousItem.interaction.interactionType {

                switch previousItem.interaction.interactionType {
                case .error:
                    if let errorMessage = interaction as? TSErrorMessage,
                       let previousErrorMessage = previousItem.interaction as? TSErrorMessage,
                       (errorMessage.errorType == .nonBlockingIdentityChange
                            || previousErrorMessage.errorType != errorMessage.errorType) {
                        itemViewState.isFirstInCluster = true
                    } else {
                        itemViewState.isFirstInCluster = false
                    }
                case .info:
                    if let infoMessage = interaction as? TSInfoMessage,
                       let previousInfoMessage = previousItem.interaction as? TSInfoMessage,
                       (infoMessage.messageType == .verificationStateChange
                            || previousInfoMessage.messageType != infoMessage.messageType) {
                        itemViewState.isFirstInCluster = true
                    } else {
                        itemViewState.isFirstInCluster = false
                    }
                case .call:
                    itemViewState.isFirstInCluster = false
                default:
                    itemViewState.isFirstInCluster = true
                }
            } else {
                itemViewState.isFirstInCluster = true
            }

            if let nextItem = nextItem,
               interaction.interactionType == nextItem.interaction.interactionType {
                switch nextItem.interaction.interactionType {
                case .error:
                    if let errorMessage = interaction as? TSErrorMessage,
                       let nextErrorMessage = nextItem.interaction as? TSErrorMessage,
                       (errorMessage.errorType == .nonBlockingIdentityChange
                            || nextErrorMessage.errorType != errorMessage.errorType) {
                        itemViewState.isLastInCluster = true
                    } else {
                        itemViewState.isLastInCluster = false
                    }
                case .info:
                    if let infoMessage = interaction as? TSInfoMessage,
                       let nextInfoMessage = nextItem.interaction as? TSInfoMessage,
                       (infoMessage.messageType == .verificationStateChange
                            || nextInfoMessage.messageType != infoMessage.messageType) {
                        itemViewState.isLastInCluster = true
                    } else {
                        itemViewState.isLastInCluster = false
                    }
                case .call:
                    itemViewState.isLastInCluster = false
                default:
                    itemViewState.isLastInCluster = true
                }
            } else {
                itemViewState.isLastInCluster = true
            }
        }

        let collapseCutoffTimestamp = NSDate.ows_millisecondsSince1970(for: viewStateSnapshot.collapseCutoffDate)
        if interaction.receivedAtTimestamp > collapseCutoffTimestamp {
            itemViewState.shouldHideFooter = false
        }

        if let nextMessage = nextItem?.interaction as? TSMessage,
           let attachment = nextMessage.mediaAttachments(with: transaction.unwrapGrdbRead).first,
           attachment.isAudio {

            itemViewState.nextAudioAttachment = AudioAttachment(attachment: attachment, owningMessage: nextMessage)
        }
    }

    private mutating func addDateHeaderViewItemIfNecessary(item: ItemBuilder) {
        let itemTimestamp = item.interaction.timestamp
        owsAssertDebug(itemTimestamp > 0)

        let itemDate = NSDate.ows_date(withMillisecondsSince1970: itemTimestamp)
        let daysBeforeToday = DateUtil.daysFrom(firstDate: itemDate, toSecondDate: todayDate)

        var shouldShowDate = false
        if let previousDaysBeforeToday = self.previousDaysBeforeToday {
            if daysBeforeToday != previousDaysBeforeToday {
                shouldShowDateOnNextViewItem = true
            }
        } else {
            // Only show for the first item if the date is not today
            shouldShowDateOnNextViewItem = daysBeforeToday != 0
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
                                   threadAssociatedData: threadAssociatedData,
                                   componentState: componentState)
            items.append(item)
        }

        self.previousDaysBeforeToday = daysBeforeToday
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
                                   threadAssociatedData: threadAssociatedData,
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
                                          threadAssociatedData: threadAssociatedData,
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
                                    threadAssociatedData: ThreadAssociatedData,
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
                           threadAssociatedData: threadAssociatedData,
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
            switch infoMessage.messageType {
            case .verificationStateChange, .typeGroupUpdate:
                return // never collapse
            case .phoneNumberChange:
                // Only collapse if the previous message was a change number for the same user
                guard case .phoneNumberChange = previousInfoMessage.messageType,
                let previousMessageUuid = previousInfoMessage.infoMessageUserInfo?[.changePhoneNumberUuid] as? String,
                let currentMessageUuid = infoMessage.infoMessageUserInfo?[.changePhoneNumberUuid] as? String else { return }
                previousItem.itemViewState.shouldCollapseSystemMessageAction = previousMessageUuid != currentMessageUuid
            default:
                // always collapse matching types
                previousItem.itemViewState.shouldCollapseSystemMessageAction
                    = previousInfoMessage.messageType == infoMessage.messageType
            }
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
    func shouldShowUnknownThreadWarning(thread: TSThread,
                                        transaction: SDSAnyReadTransaction) -> Bool {
        !canLoadOlder && Self.contactsManagerImpl.shouldShowUnknownThreadWarning(thread: thread,
                                                                                 transaction: transaction)
    }
    func shouldShowDefaultDisappearingMessageTimer(thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        GRDBThreadFinder.shouldSetDefaultDisappearingMessageTimer(thread: thread, transaction: transaction.unwrapGrdbRead)
    }
}

// MARK: -

private class ItemBuilder {
    let interaction: TSInteraction
    let thread: TSThread
    let threadAssociatedData: ThreadAssociatedData
    let componentState: CVComponentState
    var itemViewState = CVItemViewState.Builder()

    required init(interaction: TSInteraction,
                  thread: TSThread,
                  threadAssociatedData: ThreadAssociatedData,
                  componentState: CVComponentState) {
        self.interaction = interaction
        self.thread = thread
        self.threadAssociatedData = threadAssociatedData
        self.componentState = componentState
    }

    func build(coreState: CVCoreState) -> CVItemModel {
        CVItemModel(interaction: interaction,
                    thread: thread,
                    threadAssociatedData: threadAssociatedData,
                    componentState: componentState,
                    itemViewState: itemViewState.build(),
                    coreState: coreState)
    }

    var interactionType: OWSInteractionType {
        interaction.interactionType
    }

    var canShowDate: Bool {
        switch interaction.interactionType {
        case .unknown, .typingIndicator, .threadDetails, .dateHeader, .unknownThreadWarning, .defaultDisappearingMessageTimer:
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

// MARK: -

class DisplayNameCache: Dependencies {
    private var shortDisplayNameCache = [UUID: String]()

    func shortDisplayName(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        if let uuid = address.uuid, let value = shortDisplayNameCache[uuid] {
            return value
        }
        let value = contactsManager.shortDisplayName(for: address, transaction: transaction)
        if let uuid = address.uuid {
            shortDisplayNameCache[uuid] = value
        }
        return value
    }

    private var displayNameCache = [UUID: String]()

    func displayName(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        if let uuid = address.uuid, let value = displayNameCache[uuid] {
            return value
        }
        let value = contactsManager.displayName(for: address, transaction: transaction)
        if let uuid = address.uuid {
            displayNameCache[uuid] = value
        }
        return value
    }
}
