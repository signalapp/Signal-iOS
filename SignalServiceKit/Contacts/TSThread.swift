//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension TSThread {
    public typealias RowId = Int64

    public var logString: String {
        return (self as? TSGroupThread)?.groupId.toHex() ?? self.uniqueId
    }

    // MARK: - updateWith...

    public func updateWithDraft(
        draftMessageBody: MessageBody?,
        replyInfo: ThreadReplyInfo?,
        editTargetTimestamp: UInt64?,
        transaction tx: DBWriteTransaction
    ) {
        let mostRecentInteractionID = InteractionFinder.maxInteractionRowId(transaction: tx)

        anyUpdate(transaction: tx) { thread in
            thread.messageDraft = draftMessageBody?.text
            thread.messageDraftBodyRanges = draftMessageBody?.ranges
            thread.editTargetTimestamp = editTargetTimestamp.map { NSNumber(value: $0) }

            if draftMessageBody?.text.nilIfEmpty == nil {
                // 0 makes these values effectively irrelevant since they will
                // be compared to the lastInteractionRowId, which will always be > 0.
                thread.lastDraftInteractionRowId = 0
                thread.lastDraftUpdateTimestamp = 0
            } else {
                thread.lastDraftInteractionRowId = mostRecentInteractionID
                thread.lastDraftUpdateTimestamp = Date().ows_millisecondsSince1970
            }
        }

        if let replyInfo {
            DependenciesBridge.shared.threadReplyInfoStore
                .save(replyInfo, for: uniqueId, tx: tx)
        } else {
            DependenciesBridge.shared.threadReplyInfoStore
                .remove(for: uniqueId, tx: tx)
        }
    }

    public func updateWithMentionNotificationMode(
        _ mentionNotificationMode: TSThreadMentionNotificationMode,
        wasLocallyInitiated: Bool,
        transaction tx: DBWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.mentionNotificationMode = mentionNotificationMode
        }

        if
            wasLocallyInitiated,
            let groupThread = self as? TSGroupThread,
            groupThread.isGroupV2Thread
        {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(
                groupModel: groupThread.groupModel
            )
        }
    }

    /// Updates `shouldThreadBeVisible`.
    public func updateWithShouldThreadBeVisible(
        _ shouldThreadBeVisible: Bool,
        transaction tx: DBWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.shouldThreadBeVisible = true
        }
    }

    public func updateWithLastSentStoryTimestamp(
        _ lastSentStoryTimestamp: UInt64,
        transaction tx: DBWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            if lastSentStoryTimestamp > (thread.lastSentStoryTimestamp?.uint64Value ?? 0) {
                thread.lastSentStoryTimestamp = NSNumber(value: lastSentStoryTimestamp)
            }
        }
    }

    // MARK: -

    @objc
    public func updateWithInsertedInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        updateWithInteraction(interaction, wasInteractionInserted: true, tx: tx)
    }

    public func updateWithUpdatedInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction, ) {
        updateWithInteraction(interaction, wasInteractionInserted: false, tx: tx)
    }

    private func updateWithInteraction(_ interaction: TSInteraction, wasInteractionInserted: Bool, tx: DBWriteTransaction, ) {
        let db = DependenciesBridge.shared.db

        let hasLastVisibleInteraction = hasLastVisibleInteraction(transaction: tx)
        let needsToClearLastVisibleSortId = hasLastVisibleInteraction && wasInteractionInserted

        if !interaction.shouldAppearInInbox(transaction: tx) {
            // We want to clear the last visible sort ID on any new message,
            // even if the message doesn't appear in the inbox view.
            if needsToClearLastVisibleSortId {
                clearLastVisibleInteraction(transaction: tx)
            }
            scheduleTouchFinalization(transaction: tx)
            return
        }

        let interactionRowId = UInt64(interaction.sqliteRowId ?? 0)
        let needsToMarkAsVisible = !shouldThreadBeVisible
        let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: self, transaction: tx)
        let needsToClearArchived = shouldClearArchivedStatusWhenUpdatingWithInteraction(
            interaction,
            wasInteractionInserted: wasInteractionInserted,
            threadAssociatedData: threadAssociatedData,
            tx: tx
        )
        let needsToUpdateLastInteractionRowId = interactionRowId > lastInteractionRowId
        let needsToClearIsMarkedUnread = threadAssociatedData.isMarkedUnread && wasInteractionInserted

        if
            needsToMarkAsVisible
                || needsToClearArchived
                || needsToUpdateLastInteractionRowId
                || needsToClearLastVisibleSortId
                || needsToClearIsMarkedUnread
        {
            anyUpdate(transaction: tx) { thread in
                thread.shouldThreadBeVisible = true
                thread.lastInteractionRowId = max(thread.lastInteractionRowId, interactionRowId)
            }

            threadAssociatedData.clear(
                isArchived: needsToClearArchived,
                isMarkedUnread: needsToClearIsMarkedUnread,
                updateStorageService: true,
                transaction: tx
            )

            if needsToMarkAsVisible {
                // Non-visible threads don't get indexed, so if we're becoming
                // visible for the first time...
                db.touch(
                    thread: self,
                    shouldReindex: true,
                    shouldUpdateChatListUi: true,
                    tx: tx
                )
            }

            if needsToClearLastVisibleSortId {
                clearLastVisibleInteraction(transaction: tx)
            }
        } else {
            scheduleTouchFinalization(transaction: tx)
        }
    }

    private func shouldClearArchivedStatusWhenUpdatingWithInteraction(
        _ interaction: TSInteraction,
        wasInteractionInserted: Bool,
        threadAssociatedData: ThreadAssociatedData,
        tx: DBReadTransaction
    ) -> Bool {
        var needsToClearArchived = threadAssociatedData.isArchived && wasInteractionInserted

        // I'm not sure, at the time I am migrating this to Swift, if this is
        // a load-bearing check of some sort. Perhaps in the future, we can
        // more confidently remove this.
        if
            !CurrentAppContext().isRunningTests,
            !AppReadinessObjcBridge.isAppReady
        {
            needsToClearArchived = false
        }

        if let infoMessage = interaction as? TSInfoMessage {
            switch infoMessage.messageType {
            case
                    .syncedThread,
                    .threadMerge:
                needsToClearArchived = false
            case
                    .typeLocalUserEndedSession,
                    .typeRemoteUserEndedSession,
                    .userNotRegistered,
                    .typeUnsupportedMessage,
                    .typeGroupUpdate,
                    .typeGroupQuit,
                    .typeDisappearingMessagesUpdate,
                    .addToContactsOffer,
                    .verificationStateChange,
                    .addUserToProfileWhitelistOffer,
                    .addGroupToProfileWhitelistOffer,
                    .unknownProtocolVersion,
                    .userJoinedSignal,
                    .profileUpdate,
                    .phoneNumberChange,
                    .recipientHidden,
                    .paymentsActivationRequest,
                    .paymentsActivated,
                    .sessionSwitchover,
                    .reportedSpam,
                    .learnedProfileName,
                    .blockedOtherUser,
                    .blockedGroup,
                    .unblockedOtherUser,
                    .unblockedGroup,
                    .acceptedMessageRequest:
                break
            }
        }

        // Shouldn't clear archived if:
        // - The thread is muted.
        // - The user has requested we keep muted chats archived.
        // - The message was sent by someone other than the current user. (If the
        //   current user sent the message, we should clear archived.)
        let wasMessageSentByUs = interaction is TSOutgoingMessage
        if
            threadAssociatedData.isMuted,
            SSKPreferences.shouldKeepMutedChatsArchived(transaction: tx),
            !wasMessageSentByUs
        {
            needsToClearArchived = false
        }

        return needsToClearArchived
    }

    // MARK: -

    public func updateWithRemovedInteraction(
        _ interaction: TSInteraction,
        tx: DBWriteTransaction
    ) {
        let interactionRowId = interaction.sqliteRowId ?? 0
        let needsToUpdateLastInteractionRowId = interactionRowId == lastInteractionRowId

        let lastVisibleSortId = lastVisibleSortId(transaction: tx) ?? 0
        let needsToUpdateLastVisibleSortId = lastVisibleSortId > 0 && lastVisibleSortId == interactionRowId

        updateOnInteractionsRemoved(
            needsToUpdateLastInteractionRowId: needsToUpdateLastInteractionRowId,
            needsToUpdateLastVisibleSortId: needsToUpdateLastVisibleSortId,
            lastVisibleSortId: lastVisibleSortId,
            tx: tx
        )
    }

    public func updateOnInteractionsRemoved(
        needsToUpdateLastInteractionRowId: Bool,
        needsToUpdateLastVisibleSortId: Bool,
        tx: DBWriteTransaction,
    ) {
        updateOnInteractionsRemoved(
            needsToUpdateLastInteractionRowId: needsToUpdateLastInteractionRowId,
            needsToUpdateLastVisibleSortId: needsToUpdateLastVisibleSortId,
            lastVisibleSortId: lastVisibleSortId(transaction: tx) ?? 0,
            tx: tx
        )
    }

    private func updateOnInteractionsRemoved(
        needsToUpdateLastInteractionRowId: Bool,
        needsToUpdateLastVisibleSortId: Bool,
        lastVisibleSortId: UInt64,
        tx: DBWriteTransaction,
    ) {
        if needsToUpdateLastInteractionRowId || needsToUpdateLastVisibleSortId {
            anyUpdate(transaction: tx) { thread in
                if needsToUpdateLastInteractionRowId {
                    let lastInteraction = thread.lastInteractionForInbox(transaction: tx)
                    thread.lastInteractionRowId = lastInteraction?.sortId ?? 0
                }
            }

            if needsToUpdateLastVisibleSortId {
                if let interactionBeforeRemovedInteraction = firstInteraction(
                    atOrAroundSortId: lastVisibleSortId,
                    transaction: tx
                ) {
                    setLastVisibleInteraction(
                        sortId: interactionBeforeRemovedInteraction.sortId,
                        onScreenPercentage: 1.0,
                        transaction: tx
                    )
                } else {
                    clearLastVisibleInteraction(transaction: tx)
                }
            }
        } else {
            scheduleTouchFinalization(transaction: tx)
        }
    }

    // MARK: -

    @objc
    func scheduleTouchFinalization(transaction tx: DBWriteTransaction) {
        tx.addFinalizationBlock(key: uniqueId) { tx in
            let databaseStorage = SSKEnvironment.shared.databaseStorageRef

            guard let selfThread = Self.anyFetch(uniqueId: self.uniqueId, transaction: tx) else {
                return
            }

            databaseStorage.touch(thread: selfThread, shouldReindex: false, tx: tx)
        }
    }
}
