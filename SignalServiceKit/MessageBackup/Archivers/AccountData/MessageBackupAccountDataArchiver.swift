//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {
    /// An identifier for the ``BackupProto.AccountData`` backup frame.
    ///
    /// Uses a singleton pattern, as there is only ever one account data frame
    /// in a backup.
    public struct AccountDataId: MessageBackupLoggableId {
        static let localUser = AccountDataId()

        private init() {}

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProto.AccountData" }
        public var idLogString: String { "localUser" }
    }

    public enum ArchiveAccountDataResult {
        case success
        case failure(ArchiveFrameError<AccountDataId>)
    }
}

/**
 * Archives the ``BackupProto.AccountData`` frame
 */
public protocol MessageBackupAccountDataArchiver: MessageBackupProtoArchiver {
    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<MessageBackup.AccountDataId>

    func archiveAccountData(
        stream: MessageBackupProtoOutputStream,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveAccountDataResult

    func restore(
        _ accountData: BackupProto.AccountData,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult
}

public class MessageBackupAccountDataArchiverImpl: MessageBackupAccountDataArchiver {

    private let disappearingMessageConfigurationStore: DisappearingMessagesConfigurationStore
    private let localUsernameManager: LocalUsernameManager
    private let phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager
    private let preferences: MessageBackup.AccountData.Shims.Preferences
    private let profileManager: MessageBackup.Shims.ProfileManager
    private let receiptManager: MessageBackup.AccountData.Shims.ReceiptManager
    private let reactionManager: MessageBackup.AccountData.Shims.ReactionManager
    private let sskPreferences: MessageBackup.AccountData.Shims.SSKPreferences
    private let subscriptionManager: MessageBackup.AccountData.Shims.SubscriptionManager
    private let storyManager: MessageBackup.AccountData.Shims.StoryManager
    private let systemStoryManager: MessageBackup.AccountData.Shims.SystemStoryManager
    private let typingIndicators: MessageBackup.AccountData.Shims.TypingIndicators
    private let udManager: MessageBackup.AccountData.Shims.UDManager
    private let usernameEducationManager: UsernameEducationManager

    public init(
        disappearingMessageConfigurationStore: DisappearingMessagesConfigurationStore,
        localUsernameManager: LocalUsernameManager,
        phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager,
        preferences: MessageBackup.AccountData.Shims.Preferences,
        profileManager: MessageBackup.Shims.ProfileManager,
        receiptManager: MessageBackup.AccountData.Shims.ReceiptManager,
        reactionManager: MessageBackup.AccountData.Shims.ReactionManager,
        sskPreferences: MessageBackup.AccountData.Shims.SSKPreferences,
        subscriptionManager: MessageBackup.AccountData.Shims.SubscriptionManager,
        storyManager: MessageBackup.AccountData.Shims.StoryManager,
        systemStoryManager: MessageBackup.AccountData.Shims.SystemStoryManager,
        typingIndicators: MessageBackup.AccountData.Shims.TypingIndicators,
        udManager: MessageBackup.AccountData.Shims.UDManager,
        usernameEducationManager: UsernameEducationManager
    ) {
        self.disappearingMessageConfigurationStore = disappearingMessageConfigurationStore
        self.localUsernameManager = localUsernameManager
        self.phoneNumberDiscoverabilityManager = phoneNumberDiscoverabilityManager
        self.preferences = preferences
        self.receiptManager = receiptManager
        self.reactionManager = reactionManager
        self.sskPreferences = sskPreferences
        self.subscriptionManager = subscriptionManager
        self.storyManager = storyManager
        self.systemStoryManager = systemStoryManager
        self.typingIndicators = typingIndicators
        self.udManager = udManager
        self.usernameEducationManager = usernameEducationManager
        self.profileManager = profileManager
    }

    public func archiveAccountData(
        stream: MessageBackupProtoOutputStream,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveAccountDataResult {

        guard let localProfile = profileManager.getUserProfileForLocalUser(tx: tx) else {
            return .failure(.archiveFrameError(.missingLocalProfile, .localUser))
        }
        guard let profileKeyData = localProfile.profileKey?.keyData else {
            return .failure(.archiveFrameError(.missingLocalProfileKey, .localUser))
        }

        var accountData = BackupProto.AccountData(
            profileKey: profileKeyData,
            givenName: localProfile.givenName ?? "",
            familyName: localProfile.familyName ?? "",
            avatarUrlPath: localProfile.avatarUrlPath ?? "",
            subscriberId: subscriptionManager.getSubscriberID(tx: tx) ?? .init(),
            subscriberCurrencyCode: subscriptionManager.getSubscriberCurrencyCode(tx: tx) ?? "",
            subscriptionManuallyCancelled: subscriptionManager.userManuallyCancelledSubscription(tx: tx)
        )

        if let result = buildUsernameLinkProto(tx: tx) {
            accountData.username = result.username
            accountData.usernameLink = result.usernameLink
        }

        accountData.accountSettings = buildAccountSettingsProto(tx: tx)

        let error = Self.writeFrameToStream(stream, objectId: MessageBackup.AccountDataId.localUser) {
            var frame = BackupProto.Frame()
            frame.item = .account(accountData)
            return frame
        }

        if let error {
            return .failure(error)
        } else {
            return .success
        }
    }

    private func buildUsernameLinkProto(tx: DBReadTransaction) -> (username: String, usernameLink: BackupProto.AccountData.UsernameLink)? {
        switch self.localUsernameManager.usernameState(tx: tx) {
        case .unset, .linkCorrupted, .usernameAndLinkCorrupted:
            return nil
        case .available(let username, let usernameLink):
            var usernameLink = BackupProto.AccountData.UsernameLink(
                entropy: usernameLink.entropy,
                serverId: usernameLink.handle.data
            )

            let linkColor = localUsernameManager.usernameLinkQRCodeColor(tx: tx)
            switch linkColor {
            case .unknown:
                usernameLink.color = .UNKNOWN
            case .blue, .grey, .green, .olive, .orange, .pink, .purple, .white:
                usernameLink.color = linkColor.backupProtoColor
            }
            return (username, usernameLink)
        }
    }

    private func buildAccountSettingsProto(tx: DBReadTransaction) -> BackupProto.AccountData.AccountSettings {

        // Fetch all the account settings
        let readReceipts = receiptManager.areReadReceiptsEnabled(tx: tx)
        let sealedSenderIndicators = preferences.shouldShowUnidentifiedDeliveryIndicators(tx: tx)
        let typingIndicatorsEnabled = typingIndicators.areTypingIndicatorsEnabled()
        let linkPreviews = sskPreferences.areLinkPreviewsEnabled(tx: tx)
        let notDiscoverableByPhoneNumber = {
            switch phoneNumberDiscoverabilityManager.phoneNumberDiscoverability(tx: tx) {
            case .everybody:
                return false
            case .nobody, .none:
                return true
            }
        }()
        let preferContactAvatars = sskPreferences.preferContactAvatars(tx: tx)
        let universalExpireTimer = disappearingMessageConfigurationStore.fetchOrBuildDefault(for: .universal, tx: tx).durationSeconds
        let displayBadgesOnProfile = subscriptionManager.displayBadgesOnProfile(tx: tx)
        let keepMutedChatsArchived = sskPreferences.shouldKeepMutedChatsArchived(tx: tx)
        let hasSetMyStoriesPrivacy = storyManager.hasSetMyStoriesPrivacy(tx: tx)
        let hasViewedOnboardingStory = systemStoryManager.isOnboardingStoryViewed(tx: tx)
        let storiesDisabled = storyManager.areStoriesEnabled(tx: tx).negated
        let hasSeenGroupStoryEducationSheet = systemStoryManager.hasSeenGroupStoryEducationSheet(tx: tx)
        let hasCompletedUsernameOnboarding = usernameEducationManager.shouldShowUsernameEducation(tx: tx).negated

        // Optional settings
        let preferredReactionEmoji = reactionManager.customEmojiSet(tx: tx)
        let storyViewReceiptsEnabled = storyManager.areViewReceiptsEnabled(tx: tx)
        let phoneNumberSharingMode: BackupProto.AccountData.PhoneNumberSharingMode? = {
            switch udManager.phoneNumberSharingMode(tx: tx) {
            case .everybody:
                return .EVERYBODY
            case .nobody:
                return .NOBODY
            case .none:
                return .UNKNOWN
            }
        }()

        // Populate the proto with the settings
        var accountSettings = BackupProto.AccountData.AccountSettings(
            readReceipts: readReceipts,
            sealedSenderIndicators: sealedSenderIndicators,
            typingIndicators: typingIndicatorsEnabled,
            linkPreviews: linkPreviews,
            notDiscoverableByPhoneNumber: notDiscoverableByPhoneNumber,
            preferContactAvatars: preferContactAvatars,
            universalExpireTimer: universalExpireTimer,
            displayBadgesOnProfile: displayBadgesOnProfile,
            keepMutedChatsArchived: keepMutedChatsArchived,
            hasSetMyStoriesPrivacy: hasSetMyStoriesPrivacy,
            hasViewedOnboardingStory: hasViewedOnboardingStory,
            storiesDisabled: storiesDisabled,
            hasSeenGroupStoryEducationSheet: hasSeenGroupStoryEducationSheet,
            hasCompletedUsernameOnboarding: hasCompletedUsernameOnboarding
        )

        if let preferredReactionEmoji {
            accountSettings.preferredReactionEmoji = preferredReactionEmoji
        }
        accountSettings.storyViewReceiptsEnabled = storyViewReceiptsEnabled
        accountSettings.phoneNumberSharingMode = phoneNumberSharingMode

        return accountSettings
    }

    public func restore(
        _ accountData: BackupProto.AccountData,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        guard let profileKey = OWSAES256Key(data: accountData.profileKey) else {
            return .failure([.restoreFrameError(
                .invalidProtoData(.invalidLocalProfileKey),
                .localUser
            )])
        }

        // Given name and profile key are required for the local profile. The
        // rest are optional.
        profileManager.insertLocalUserProfile(
            givenName: accountData.givenName,
            familyName: accountData.familyName.nilIfEmpty,
            avatarUrlPath: accountData.avatarUrlPath.nilIfEmpty,
            profileKey: profileKey,
            tx: tx
        )

        // Restore Subscription data, if nod a default value
        if accountData.subscriberId.count > 0, accountData.subscriberCurrencyCode.count > 0 {
            subscriptionManager.setSubscriberID(subscriberID: accountData.subscriberId, tx: tx)
            subscriptionManager.setSubscriberCurrencyCode(currencyCode: accountData.subscriberCurrencyCode, tx: tx)
        }
        subscriptionManager.setUserManuallyCancelledSubscription(value: accountData.subscriptionManuallyCancelled, tx: tx)

        // Restore local settings
        if let settings = accountData.accountSettings {
            receiptManager.setAreReadReceiptsEnabled(value: settings.readReceipts, tx: tx)
            preferences.setShouldShowUnidentifiedDeliveryIndicators(value: settings.sealedSenderIndicators, tx: tx)
            typingIndicators.setTypingIndicatorsEnabled(value: settings.typingIndicators, tx: tx)
            sskPreferences.setAreLinkPreviewsEnabled(value: settings.linkPreviews, tx: tx)
            phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                settings.notDiscoverableByPhoneNumber ? .nobody : .everybody,
                updateAccountAttributes: false, // This should be updated later, similar to storage service
                updateStorageService: false,
                authedAccount: .implicit(),
                tx: tx
            )
            sskPreferences.setPreferContactAvatars(value: settings.preferContactAvatars, tx: tx)

            let token = DisappearingMessageToken(
                isEnabled: settings.universalExpireTimer > 0,
                durationSeconds: settings.universalExpireTimer
            )
            disappearingMessageConfigurationStore.set(token: token, for: .universal, tx: tx)

            subscriptionManager.setDisplayBadgesOnProfile(value: settings.displayBadgesOnProfile, tx: tx)
            sskPreferences.setShouldKeepMutedChatsArchived(value: settings.keepMutedChatsArchived, tx: tx)
            storyManager.setHasSetMyStoriesPrivacy(value: settings.hasSetMyStoriesPrivacy, tx: tx)
            systemStoryManager.setHasViewedOnboardingStory(value: settings.hasViewedOnboardingStory, tx: tx)
            storyManager.setAreStoriesEnabled(value: settings.storiesDisabled.negated, tx: tx)
            systemStoryManager.setHasSeenGroupStoryEducationSheet(value: settings.hasSeenGroupStoryEducationSheet, tx: tx)
            usernameEducationManager.setShouldShowUsernameEducation(settings.hasCompletedUsernameOnboarding.negated, tx: tx)

            if settings.preferredReactionEmoji.count > 0 {
                reactionManager.setCustomEmojiSet(emojis: settings.preferredReactionEmoji, tx: tx)
            }
            if let storyViewReceiptsEnabled = settings.storyViewReceiptsEnabled {
                storyManager.setAreViewReceiptsEnabled(value: storyViewReceiptsEnabled, tx: tx)
            }

            let phoneNumberSharingMode: PhoneNumberSharingMode = {
                switch settings.phoneNumberSharingMode {
                case .UNKNOWN, .none:
                    return .defaultValue
                case .EVERYBODY:
                    return .everybody
                case .NOBODY:
                    return .nobody
                }
            }()
            udManager.setPhoneNumberSharingMode(phoneNumberSharingMode, tx: tx)
        }

        // Restore username details (username, link, QR color)
        if let username = accountData.username, let usernameLink = accountData.usernameLink {
            if
                let handle = UUID(data: usernameLink.serverId),
                let linkData = Usernames.UsernameLink(handle: handle, entropy: usernameLink.entropy)
            {
                localUsernameManager.setLocalUsername(username: username, usernameLink: linkData, tx: tx)
            } else {
                return .failure([.restoreFrameError(.invalidProtoData(.invalidLocalUsernameLink), .localUser)])
            }
        }

        if let color = accountData.usernameLink?.color {
            localUsernameManager.setUsernameLinkQRCodeColor(color: color.qrCodeColor, tx: tx)
        }

        return .success
    }
}

private extension Usernames.QRCodeColor {
    var backupProtoColor: BackupProto.AccountData.UsernameLink.Color {
        switch self {
        case .blue: return .BLUE
        case .white: return .WHITE
        case .grey: return .GREY
        case .olive: return .OLIVE
        case .green: return .GREEN
        case .orange: return .ORANGE
        case .pink: return .PINK
        case .purple: return .PURPLE
        }
    }
}

private extension BackupProto.AccountData.UsernameLink.Color {
    var qrCodeColor: Usernames.QRCodeColor {
        switch self {
        case .BLUE: return .blue
        case .WHITE: return .white
        case .GREY: return .grey
        case .OLIVE: return .olive
        case .GREEN: return .green
        case .ORANGE: return .orange
        case .PINK: return .pink
        case .PURPLE: return .purple
        case .UNKNOWN: return .unknown
        }
    }
}
