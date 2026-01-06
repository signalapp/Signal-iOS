//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Intents
import LibSignalClient

// MARK: - Enqueue messages

public final class ThreadUtil {

    public typealias PersistenceCompletion = () -> Void

    // A serial queue that ensures that messages are sent in the
    // same order in which they are enqueued.
    public static var enqueueSendQueue = SerialTaskQueue()

    public static func enqueueSendAsyncWrite(_ block: @escaping (DBWriteTransaction) -> Void) {
        enqueueSendQueue.enqueue {
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                block(transaction)
            }
        }
    }

    private static func applyDisappearingMessagesConfiguration(to builder: TSOutgoingMessageBuilder, tx: DBReadTransaction) {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(builder.thread), tx: tx)
        builder.expiresInSeconds = dmConfig.durationSeconds
        builder.expireTimerVersion = NSNumber(value: dmConfig.timerVersion)
    }

    public class func enqueueMessagePromise(
        message: PreparedOutgoingMessage,
        limitToCurrentProcessLifetime: Bool = false,
        isHighPriority: Bool = false,
        transaction: DBWriteTransaction,
    ) -> Promise<Void> {
        let promise = SSKEnvironment.shared.messageSenderJobQueueRef.add(
            .promise,
            message: message,
            limitToCurrentProcessLifetime: limitToCurrentProcessLifetime,
            isHighPriority: isHighPriority,
            transaction: transaction,
        )
        if let messageForIntent = message.messageForIntentDonation(tx: transaction) {
            messageForIntent.thread(tx: transaction)?.donateSendMessageIntent(for: messageForIntent, transaction: transaction)
        }
        return promise
    }
}

// MARK: - Contact Shares

public extension ThreadUtil {

    @discardableResult
    class func enqueueMessage(
        withContactShare contactShareDraft: ContactShareDraft,
        thread: TSThread,
    ) -> TSOutgoingMessage {
        AssertIsOnMainThread()
        assert(contactShareDraft.ows_isValid)

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread)

        let message: TSOutgoingMessage = SSKEnvironment.shared.databaseStorageRef.read { tx in
            applyDisappearingMessagesConfiguration(to: builder, tx: tx)
            return builder.build(transaction: tx)
        }

        Self.enqueueSendQueue.enqueue {
            guard
                let sendableContactShareDraft = try? await DependenciesBridge.shared.contactShareManager
                    .validateAndPrepare(draft: contactShareDraft)
            else {
                owsFailDebug("Failed to build contact share")
                return
            }

            // stickers don't have bodies
            owsPrecondition(message.body == nil)
            let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
                message,
                body: nil,
                contactShareDraft: sendableContactShareDraft,
            )

            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                guard let preparedMessage = try? unpreparedMessage.prepare(tx: transaction) else {
                    owsFailDebug("Unable to build message for sending!")
                    return
                }
                SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
                if
                    let messageForIntent = preparedMessage.messageForIntentDonation(tx: transaction),
                    let thread = messageForIntent.thread(tx: transaction)
                {
                    thread.donateSendMessageIntent(for: messageForIntent, transaction: transaction)
                }
            }
        }

        return message
    }
}

// MARK: - Stickers

public extension ThreadUtil {

    @discardableResult
    class func enqueueMessage(withInstalledSticker stickerInfo: StickerInfo, thread: TSThread) -> TSOutgoingMessage {
        AssertIsOnMainThread()

        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread)
        let message = SSKEnvironment.shared.databaseStorageRef.read { tx in
            applyDisappearingMessagesConfiguration(to: builder, tx: tx)
            return builder.build(transaction: tx)
        }

        Self.enqueueSendQueue.enqueue {
            let stickerDraft: MessageStickerDraft? = SSKEnvironment.shared.databaseStorageRef.read { tx in
                guard let stickerMetadata = StickerManager.installedStickerMetadata(stickerInfo: stickerInfo, transaction: tx) else {
                    owsFailDebug("Could not find sticker file.")
                    return nil
                }

                guard let stickerData = try? stickerMetadata.readStickerData() else {
                    owsFailDebug("Couldn't load sticker data.")
                    return nil
                }

                return MessageStickerDraft(
                    info: stickerInfo,
                    stickerData: stickerData,
                    stickerType: stickerMetadata.stickerType,
                    emoji: stickerMetadata.firstEmoji,
                )
            }

            guard let stickerDraft else {
                return
            }

            let stickerDataSource: MessageStickerDataSource
            do {
                stickerDataSource = try await DependenciesBridge.shared.messageStickerManager.buildDataSource(
                    fromDraft: stickerDraft,
                )
            } catch {
                owsFailDebug("Failed to build sticker!")
                return
            }
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                self.enqueueMessage(message, stickerDataSource: stickerDataSource, thread: thread, tx: tx)
            }
        }

        return message
    }

    @discardableResult
    class func enqueueMessage(
        withUninstalledSticker stickerMetadata: any StickerMetadata,
        stickerData: Data,
        thread: TSThread,
    ) -> TSOutgoingMessage {
        AssertIsOnMainThread()

        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread)
        let message = SSKEnvironment.shared.databaseStorageRef.read { tx in
            applyDisappearingMessagesConfiguration(to: builder, tx: tx)
            return builder.build(transaction: tx)
        }

        let stickerDraft = MessageStickerDraft(
            info: stickerMetadata.stickerInfo,
            stickerData: stickerData,
            stickerType: stickerMetadata.stickerType,
            emoji: stickerMetadata.firstEmoji,
        )

        Self.enqueueSendQueue.enqueue {
            let stickerDataSource: MessageStickerDataSource
            do {
                stickerDataSource = try await DependenciesBridge.shared.messageStickerManager.buildDataSource(
                    fromDraft: stickerDraft,
                )
            } catch {
                owsFailDebug("Failed to build sticker!")
                return
            }
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                self.enqueueMessage(message, stickerDataSource: stickerDataSource, thread: thread, tx: tx)
            }
        }

        return message
    }

    private class func enqueueMessage(
        _ message: TSOutgoingMessage,
        stickerDataSource: MessageStickerDataSource,
        thread: TSThread,
        tx: DBWriteTransaction,
    ) {
        AssertNotOnMainThread()

        // stickers don't have bodies
        owsPrecondition(message.body == nil)

        let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
            message,
            body: nil,
            messageStickerDraft: stickerDataSource,
        )
        let preparedMessage: PreparedOutgoingMessage
        do {
            preparedMessage = try unpreparedMessage.prepare(tx: tx)
        } catch {
            return owsFailDebug("Couldn't prepare message: \(error)")
        }

        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)

        if let messageForIntent = preparedMessage.messageForIntentDonation(tx: tx) {
            thread.donateSendMessageIntent(for: messageForIntent, transaction: tx)
        }
    }
}

// MARK: - Profile Whitelist

extension ThreadUtil {
    /// Should we set the universal timer for this contact thread?
    /// - Note
    /// Group threads never go through this method, and instead have their
    /// disappearing-message timer set during group creation.
    private static func shouldSetUniversalTimer(contactThread: TSContactThread, tx: DBReadTransaction) -> Bool {
        ThreadFinder().shouldSetDefaultDisappearingMessageTimer(
            contactThread: contactThread,
            transaction: tx,
        )
    }

    private static func setUniversalTimer(contactThread: TSContactThread, tx: DBWriteTransaction) {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmUniversalToken = dmConfigurationStore.fetchOrBuildDefault(for: .universal, tx: tx)
        let version = dmConfigurationStore.fetchOrBuildDefault(
            for: .thread(contactThread),
            tx: tx,
        ).timerVersion
        let dmResult = dmConfigurationStore.set(
            token: .init(
                isEnabled: dmUniversalToken.isEnabled,
                durationSeconds: dmUniversalToken.durationSeconds,
                version: version,
            ),
            for: .thread(contactThread),
            tx: tx,
        )
        OWSDisappearingConfigurationUpdateInfoMessage(
            contactThread: contactThread,
            timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
            isConfigurationEnabled: dmResult.newConfiguration.isEnabled,
            configurationDurationSeconds: dmResult.newConfiguration.durationSeconds,
            createdByRemoteName: nil,
        ).anyInsert(transaction: tx)
    }

    private static func shouldAddThreadToProfileWhitelist(_ thread: TSThread, tx: DBReadTransaction) -> Bool {
        let hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: tx)

        // If we're creating this thread or we have a pending message request,
        // any action we trigger should share our profile.
        return !thread.shouldThreadBeVisible || hasPendingMessageRequest
    }

    @discardableResult
    public class func addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(
        _ thread: TSThread,
    ) -> Bool {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        let threadAsContactThread = thread as? TSContactThread

        let (shouldSetUniversalTimer, shouldAddToProfileWhitelist) = databaseStorage.read { tx -> (Bool, Bool) in
            let universalTimer: Bool = {
                guard let threadAsContactThread else { return false }
                return Self.shouldSetUniversalTimer(contactThread: threadAsContactThread, tx: tx)
            }()
            let profileWhitelist = shouldAddThreadToProfileWhitelist(thread, tx: tx)

            return (universalTimer, profileWhitelist)
        }
        if shouldSetUniversalTimer, let threadAsContactThread {
            databaseStorage.write { tx in setUniversalTimer(contactThread: threadAsContactThread, tx: tx) }
        }
        if shouldAddToProfileWhitelist {
            databaseStorage.write { tx in
                switch thread {
                case let thread as TSGroupThread:
                    profileManager.addGroupId(
                        toProfileWhitelist: thread.groupModel.groupId,
                        userProfileWriter: .localUser,
                        transaction: tx,
                    )
                case let thread as TSContactThread:
                    if var recipient = recipientFetcher.fetchOrCreate(address: thread.contactAddress, tx: tx) {
                        profileManager.addRecipientToProfileWhitelist(
                            &recipient,
                            userProfileWriter: .localUser,
                            tx: tx,
                        )
                    }
                default:
                    owsFailDebug("can't whitelist \(type(of: thread))")
                }
            }
        }
        return shouldAddToProfileWhitelist
    }

    @discardableResult
    public class func addThreadToProfileWhitelistIfEmptyOrPendingRequest(
        _ thread: TSThread,
        setDefaultTimerIfNecessary: Bool,
        tx: DBWriteTransaction,
    ) -> Bool {
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        if
            setDefaultTimerIfNecessary,
            let contactThread = thread as? TSContactThread,
            shouldSetUniversalTimer(contactThread: contactThread, tx: tx)
        {
            setUniversalTimer(contactThread: contactThread, tx: tx)
        }
        let shouldAddToProfileWhitelist = shouldAddThreadToProfileWhitelist(thread, tx: tx)
        if shouldAddToProfileWhitelist {
            switch thread {
            case let thread as TSGroupThread:
                profileManager.addGroupId(
                    toProfileWhitelist: thread.groupModel.groupId,
                    userProfileWriter: .localUser,
                    transaction: tx,
                )
            case let thread as TSContactThread:
                if var recipient = recipientFetcher.fetchOrCreate(address: thread.contactAddress, tx: tx) {
                    profileManager.addRecipientToProfileWhitelist(
                        &recipient,
                        userProfileWriter: .localUser,
                        tx: tx,
                    )
                }
            default:
                owsFailDebug("can't whitelist \(type(of: thread))")
            }
        }
        return shouldAddToProfileWhitelist
    }
}

// MARK: - Polls

public extension ThreadUtil {

    class func enqueueMessage(
        withPoll poll: CreatePollMessage,
        thread: TSThread,
    ) {
        AssertIsOnMainThread()
        guard
            poll.question.count <= OWSPoll.Constants.maxCharacterLength,
            poll.question.trimmedIfNeeded(maxByteCount: OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes) == nil
        else {
            owsFailDebug("Poll question too large")
            return
        }

        let validatedPollQuestion = SSKEnvironment.shared.databaseStorageRef.write { tx in DependenciesBridge.shared.attachmentContentValidator.truncatedMessageBodyForInlining(
            MessageBody(text: poll.question, ranges: .empty),
            tx: tx,
        )
        }

        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: validatedPollQuestion)
        let message: TSOutgoingMessage = SSKEnvironment.shared.databaseStorageRef.read { tx in
            applyDisappearingMessagesConfiguration(to: builder, tx: tx)
            return builder.build(transaction: tx)
        }

        let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
            message,
            body: nil,
            poll: poll,
        )

        Self.enqueueSendQueue.enqueue {
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                guard let preparedMessage = try? unpreparedMessage.prepare(tx: transaction) else {
                    owsFailDebug("Unable to build message for sending!")
                    return
                }
                SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
                if
                    let messageForIntent = preparedMessage.messageForIntentDonation(tx: transaction),
                    let thread = messageForIntent.thread(tx: transaction)
                {
                    thread.donateSendMessageIntent(for: messageForIntent, transaction: transaction)
                }
            }
        }
    }
}

// MARK: - Sharing Suggestions

extension TSThread {

    /// This function should be called every time the user
    /// initiates message sending via the UI. It should *not*
    /// be called for messages we send automatically, like
    /// receipts.
    public func donateSendMessageIntent(for outgoingMessage: TSOutgoingMessage, transaction tx: DBReadTransaction) {
        // Never donate for story sends or replies, we don't want them as share suggestions
        if (outgoingMessage is OutgoingStoryMessage) || outgoingMessage.isGroupStoryReply {
            return
        }

        let sendMessageIntentBuilder = _generateSendMessageIntent(context: .outgoingMessage(outgoingMessage), transaction: tx)
        guard let sendMessageIntentBuilder else {
            return
        }

        // We don't need to wait for names to resolve here because these are
        // outgoing messages where we should already have a name.
        let interaction = INInteraction(intent: sendMessageIntentBuilder.value(tx: tx), response: nil)
        interaction.groupIdentifier = uniqueId
        interaction.direction = .outgoing
        interaction.donate(completion: { error in
            guard let error else { return }
            owsFailDebug("Failed to donate message intent for \(self.uniqueId) \(error)")
        })
    }

    public enum IntentContext {
        case senderAddress(SignalServiceAddress)
        case incomingMessage(TSIncomingMessage)
        case outgoingMessage(TSOutgoingMessage)
    }

    func generateSendMessageIntent(
        context: IntentContext,
        transaction: DBReadTransaction,
    ) -> ResolvableValue<INIntent>? {
        let builder = _generateSendMessageIntent(context: context, transaction: transaction)
        return builder?.resolvableValue(
            db: SSKEnvironment.shared.databaseStorageRef,
            profileFetcher: SSKEnvironment.shared.profileFetcherRef,
            tx: transaction,
        )
    }

    private func _generateSendMessageIntent(
        context: IntentContext,
        transaction: DBReadTransaction,
    ) -> ResolvableDisplayNameBuilder<INIntent>? {
        guard SSKPreferences.areIntentDonationsEnabled(transaction: transaction) else {
            return nil
        }

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: transaction) else {
            owsFailDebug("Not registered.")
            return nil
        }

        let senderAddress: SignalServiceAddress
        let message: TSMessage?
        let recipientAddress: SignalServiceAddress?
        switch context {
        case .outgoingMessage(let outgoingMessage):
            senderAddress = localIdentifiers.aciAddress
            message = outgoingMessage
            // For 1:1 outgoing messages, we must populate the recipient of the message,
            // otherwise sharing suggestions won't be populated correctly.
            recipientAddress = (self as? TSContactThread)?.contactAddress
        case .incomingMessage(let incomingMessage):
            senderAddress = incomingMessage.authorAddress
            message = incomingMessage
            recipientAddress = nil
        case .senderAddress(let address):
            senderAddress = address
            message = nil
            recipientAddress = nil
        }

        let isGroupStoryReply = isGroupThread && message?.isGroupStoryReply == true

        let groupThreadName = (self as? TSGroupThread)?.groupNameOrDefault
        let formattedGroupThreadName = groupThreadName.map {
            if isGroupStoryReply {
                let format = OWSLocalizedString(
                    "QUOTED_REPLY_STORY_AUTHOR_INDICATOR_FORMAT",
                    comment: "Message header when you are quoting a story. Embeds {{ story author name }}",
                )
                return String(format: format, $0)
            }
            return $0
        }

        // Uniquely namespace the notifications for group stories.
        let conversationIdentifier = isGroupStoryReply ? (uniqueId + "_groupStory") : uniqueId

        var donationMetadata: INSendMessageIntentDonationMetadata?
        if isGroupThread {
            donationMetadata = INSendMessageIntentDonationMetadata()
            donationMetadata?.recipientCount = recipientAddresses(with: transaction).count

            if let message {
                let mentionedAcis = MentionFinder.mentionedAcis(for: message, tx: transaction)
                donationMetadata?.mentionsCurrentUser = mentionedAcis.contains(localIdentifiers.aci)
                donationMetadata?.isReplyToCurrentUser = message.quotedMessage?.authorAddress == localIdentifiers.aciAddress
            }
        }
        let speakableGroupNameImage = isGroupThread ? intentThreadAvatarImage(transaction: transaction) : nil
        let recipientPerson = recipientAddress.map {
            return Self.buildPerson(
                address: $0,
                displayName: SSKEnvironment.shared.contactManagerRef.displayName(for: $0, tx: transaction),
                tx: transaction,
            )
        }

        return ResolvableDisplayNameBuilder(
            displayNameForAddress: senderAddress,
            transformedBy: { senderDisplayName, tx in
                let senderPerson = Self.buildPerson(address: senderAddress, displayName: senderDisplayName, tx: tx)
                let sendMessageIntent = INSendMessageIntent(
                    recipients: [recipientPerson].compacted(),
                    outgoingMessageType: .outgoingMessageText,
                    content: nil,
                    speakableGroupName: formattedGroupThreadName.map(INSpeakableString.init(spokenPhrase:)),
                    conversationIdentifier: conversationIdentifier,
                    serviceName: nil,
                    sender: senderPerson,
                    attachments: nil,
                )
                if let speakableGroupNameImage {
                    sendMessageIntent.setImage(speakableGroupNameImage, forParameterNamed: \.speakableGroupName)
                }
                if let donationMetadata {
                    sendMessageIntent.donationMetadata = donationMetadata
                }
                return sendMessageIntent
            },
            contactManager: SSKEnvironment.shared.contactManagerRef,
        )
    }

    func generateIncomingCallIntent(
        callerAci: Aci,
        tx: DBReadTransaction,
    ) -> ResolvableValue<INIntent>? {
        if self.isGroupThread {
            // Fall back to a "send message" intent for group calls,
            // because the "start call" intent makes the notification look too much like a 1:1 call.
            return self.generateSendMessageIntent(
                context: .senderAddress(SignalServiceAddress(callerAci)),
                transaction: tx,
            )
        } else {
            guard SSKPreferences.areIntentDonationsEnabled(transaction: tx) else {
                return nil
            }

            return ResolvableDisplayNameBuilder(
                displayNameForAddress: SignalServiceAddress(callerAci),
                transformedBy: { displayName, tx in
                    let caller = Self.buildPerson(address: SignalServiceAddress(callerAci), displayName: displayName, tx: tx)
                    return INStartCallIntent(
                        callRecordFilter: nil,
                        callRecordToCallBack: nil,
                        audioRoute: .unknown,
                        destinationType: .normal,
                        contacts: [caller],
                        callCapability: .unknown,
                    )
                },
                contactManager: SSKEnvironment.shared.contactManagerRef,
            ).resolvableValue(
                db: SSKEnvironment.shared.databaseStorageRef,
                profileFetcher: SSKEnvironment.shared.profileFetcherRef,
                tx: tx,
            )
        }
    }

    private static func buildPerson(
        address: SignalServiceAddress,
        displayName: DisplayName,
        tx: DBReadTransaction,
    ) -> INPerson {
        let nameComponents: PersonNameComponents?
        switch displayName {
        case .nickname(let nickname):
            nameComponents = nickname.nameComponents
        case .systemContactName(let systemContactName):
            nameComponents = systemContactName.nameComponents
        case .profileName(let profileNameComponents):
            nameComponents = profileNameComponents
        case .phoneNumber, .username, .deletedAccount, .unknown:
            nameComponents = nil
        }

        var filteredNameComponents = PersonNameComponents()
        filteredNameComponents.givenName = nameComponents?.givenName?.filterForDisplay
        filteredNameComponents.familyName = nameComponents?.familyName?.filterForDisplay
        filteredNameComponents.nickname = nameComponents?.nickname?.filterForDisplay

        // Generate contact handle
        let handle: INPersonHandle
        let suggestionType: INPersonSuggestionType
        if let phoneNumber = address.phoneNumber {
            handle = INPersonHandle(value: phoneNumber, type: .phoneNumber, label: nil)
            suggestionType = .none
        } else {
            handle = INPersonHandle(value: address.serviceIdUppercaseString, type: .unknown, label: nil)
            suggestionType = .instantMessageAddress
        }

        // Generate avatar
        let image = intentRecipientAvatarImage(recipient: address, transaction: tx)
        return INPerson(
            personHandle: handle,
            nameComponents: nameComponents,
            displayName: displayName.resolvedValue(),
            image: image,
            contactIdentifier: nil,
            customIdentifier: nil,
            isMe: false,
            suggestionType: suggestionType,
        )
    }

    // Use the same point size as chat list avatars, so it's likely cached and ready for the NSE.
    // The NSE cannot read the device scale, so we rely on a cached scale to correctly calculate
    // the appropriate pixel size for our avatars.
    private static let intentAvatarDiameterPixels: CGFloat = 56 * SSKEnvironment.shared.preferencesRef.cachedDeviceScale

    public func intentStoryAvatarImage(tx: DBReadTransaction) -> INImage? {
        if let storyThread = self as? TSPrivateStoryThread {
            if storyThread.isMyStory {
                guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
                    Logger.warn("Missing local address")
                    return nil
                }
                return Self.intentRecipientAvatarImage(recipient: localAddress, transaction: tx)
            } else {
                let rawImage = UIImage(named: "custom-story-light-36")
                return rawImage?.pngData().map(INImage.init(imageData:))
            }
        } else {
            return intentThreadAvatarImage(transaction: tx)
        }
    }

    private static func intentRecipientAvatarImage(recipient: SignalServiceAddress, transaction: DBReadTransaction) -> INImage? {
        // Generate avatar
        let image: INImage
        if
            let contactAvatar = SSKEnvironment.shared.avatarBuilderRef.avatarImage(
                forAddress: recipient,
                diameterPixels: Self.intentAvatarDiameterPixels,
                localUserDisplayMode: .asUser,
                transaction: transaction,
            ),
            let contactAvatarPNG = contactAvatar.pngData()
        {
            image = INImage(imageData: contactAvatarPNG)
        } else {
            image = INImage(named: "profile-placeholder-56")
        }
        return image
    }

    private func intentThreadAvatarImage(transaction: DBReadTransaction) -> INImage? {
        let image: INImage
        if
            let threadAvatar = SSKEnvironment.shared.avatarBuilderRef.avatarImage(
                forThread: self,
                diameterPixels: Self.intentAvatarDiameterPixels,
                localUserDisplayMode: .noteToSelf,
                transaction: transaction,
            ),
            let threadAvatarPng = threadAvatar.pngData()
        {
            image = INImage(imageData: threadAvatarPng)
        } else {
            image = INImage(named: isGroupThread ? "group-placeholder-56" : "profile-placeholder-56")
        }
        return image
    }
}
