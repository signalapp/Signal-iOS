//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

extension BackupArchive {
    enum Shims {
        typealias BlockingManager = _MessageBackup_BlockingManagerShim
        typealias ContactManager = _MessageBackup_ContactManagerShim
        typealias DonationSubscriptionManager = _MessageBackup_DonationSubscriptionManagerShim
        typealias ImageQuality = _MessageBackup_ImageQualityShim
        typealias OWS2FAManager = _MessageBackup_OWS2FAManagerShim
        typealias Preferences = _MessageBackup_PreferencesShim
        typealias ProfileManager = _MessageBackup_ProfileManagerShim
        typealias ReactionManager = _MessageBackup_ReactionManagerShim
        typealias ReceiptManager = _MessageBackup_ReceiptManagerShim
        typealias ScreenLock = _MessageBackup_ScreenLockShim
        typealias SSKPreferences = _MessageBackup_SSKPreferencesShim
        typealias StoryManager = _MessageBackup_StoryManagerShim
        typealias SystemStoryManager = _MessageBackup_SystemStoryManagerShim
        typealias TypingIndicators = _MessageBackup_TypingIndicatorsShim
        typealias UDManager = _MessageBackup_UDManagerShim
    }

    enum Wrappers {
        typealias BlockingManager = _MessageBackup_BlockingManagerWrapper
        typealias ContactManager = _MessageBackup_ContactManagerWrapper
        typealias DonationSubscriptionManager = _MessageBackup_DonationSubscriptionManagerWrapper
        typealias ImageQuality = _MessageBackup_ImageQualityWrapper
        typealias OWS2FAManager = _MessageBackup_OWS2FAManagerWrapper
        typealias Preferences = _MessageBackup_PreferencesWrapper
        typealias ProfileManager = _MessageBackup_ProfileManagerWrapper
        typealias ReactionManager = _MessageBackup_ReactionManagerWrapper
        typealias ReceiptManager = _MessageBackup_ReceiptManagerWrapper
        typealias ScreenLock = _MessageBackup_ScreenLockWrapper
        typealias SSKPreferences = _MessageBackup_SSKPreferencesWrapper
        typealias StoryManager = _MessageBackup_StoryManagerWrapper
        typealias SystemStoryManager = _MessageBackup_SystemStoryManagerWrapper
        typealias TypingIndicators = _MessageBackup_TypingIndicatorsWrapper
        typealias UDManager = _MessageBackup_UDManagerWrapper
    }
}

// MARK: - BlockingManager

protocol _MessageBackup_BlockingManagerShim {

    func addBlockedRecipient(_ recipient: inout SignalRecipient, blockedAt: BlockedTimestamp, tx: DBWriteTransaction)
    func addBlockedGroup(_ groupRecord: inout GroupRecord, blockedAt: BlockedTimestamp, tx: DBWriteTransaction)
}

class _MessageBackup_BlockingManagerWrapper: _MessageBackup_BlockingManagerShim {

    private let blockingManager: BlockingManager

    init(_ blockingManager: BlockingManager) {
        self.blockingManager = blockingManager
    }

    func addBlockedRecipient(_ recipient: inout SignalRecipient, blockedAt: BlockedTimestamp, tx: DBWriteTransaction) {
        blockingManager.addBlockedRecipient(&recipient, blockedAt: blockedAt, blockMode: .backupRestore, tx: tx)
    }

    func addBlockedGroup(_ groupRecord: inout GroupRecord, blockedAt: BlockedTimestamp, tx: DBWriteTransaction) {
        blockingManager.addBlockedGroup(&groupRecord, blockedAt: blockedAt, blockMode: .backupRestore, tx: tx)
    }
}

// MARK: - ContactManager

protocol _MessageBackup_ContactManagerShim {
    func displayName(_ address: SignalServiceAddress, tx: DBWriteTransaction) -> String
    func fetchSignalAccount(_ address: SignalServiceAddress, tx: DBReadTransaction) -> SignalAccount?
    func insertSignalAccount(_ account: SignalAccount, tx: DBWriteTransaction)
}

class _MessageBackup_ContactManagerWrapper: _MessageBackup_ContactManagerShim {
    private let contactManager: any ContactManager

    init(_ contactManager: any ContactManager) {
        self.contactManager = contactManager
    }

    func displayName(_ address: SignalServiceAddress, tx: DBWriteTransaction) -> String {
        return contactManager.displayName(for: address, tx: tx).resolvedValue()
    }

    func fetchSignalAccount(_ address: SignalServiceAddress, tx: DBReadTransaction) -> SignalAccount? {
        return contactManager.fetchSignalAccount(for: address, transaction: tx)
    }

    func insertSignalAccount(_ account: SignalAccount, tx: DBWriteTransaction) {
        account.anyInsert(transaction: tx)
    }
}

// MARK: - DonationSubscriptionManager

protocol _MessageBackup_DonationSubscriptionManagerShim {
    func displayBadgesOnProfile(tx: DBReadTransaction) -> Bool
    func setDisplayBadgesOnProfile(value: Bool, tx: DBWriteTransaction)
    func getSubscriberID(tx: DBReadTransaction) -> Data?
    func setSubscriberID(subscriberID: Data, tx: DBWriteTransaction)
    func getSubscriberCurrencyCode(tx: DBReadTransaction) -> String?
    func setSubscriberCurrencyCode(currencyCode: Currency.Code?, tx: DBWriteTransaction)
    func userManuallyCancelledSubscription(tx: DBReadTransaction) -> Bool
    func setUserManuallyCancelledSubscription(value: Bool, tx: DBWriteTransaction)
}

class _MessageBackup_DonationSubscriptionManagerWrapper: _MessageBackup_DonationSubscriptionManagerShim {
    private let donationSubscriptionManager: DonationSubscriptionManager

    init(_ donationSubscriptionManager: DonationSubscriptionManager) {
        self.donationSubscriptionManager = donationSubscriptionManager
    }

    func displayBadgesOnProfile(tx: DBReadTransaction) -> Bool {
        donationSubscriptionManager.displayBadgesOnProfile(tx: tx)
    }

    func setDisplayBadgesOnProfile(value: Bool, tx: DBWriteTransaction) {
        donationSubscriptionManager.setDisplayBadgesOnProfile(value, updateStorageService: false, tx: tx)
    }

    func getSubscriberID(tx: DBReadTransaction) -> Data? {
        donationSubscriptionManager.getSubscriberID(tx: tx)
    }

    func setSubscriberID(subscriberID: Data, tx: DBWriteTransaction) {
        donationSubscriptionManager.setSubscriberID(subscriberID, tx: tx)
    }

    func getSubscriberCurrencyCode(tx: DBReadTransaction) -> String? {
        donationSubscriptionManager.getSubscriberCurrencyCode(tx: tx)
    }

    func setSubscriberCurrencyCode(currencyCode: Currency.Code?, tx: DBWriteTransaction) {
        donationSubscriptionManager.setSubscriberCurrencyCode(currencyCode, tx: tx)
    }

    func userManuallyCancelledSubscription(tx: DBReadTransaction) -> Bool {
        donationSubscriptionManager.userManuallyCancelledSubscription(tx: tx)
    }

    func setUserManuallyCancelledSubscription(value: Bool, tx: DBWriteTransaction) {
        donationSubscriptionManager.setUserManuallyCancelledSubscription(value, updateStorageService: false, tx: tx)
    }
}

// MARK: - ImageQuality

protocol _MessageBackup_ImageQualityShim {
    func setValue(_ imageQuality: ImageQuality, tx: DBWriteTransaction)
    func fetchValue(tx: DBReadTransaction) -> ImageQuality
}

class _MessageBackup_ImageQualityWrapper: _MessageBackup_ImageQualityShim {
    func setValue(_ imageQuality: ImageQuality, tx: DBWriteTransaction) {
        ImageQuality.setValue(imageQuality, tx: tx)
    }

    func fetchValue(tx: DBReadTransaction) -> ImageQuality {
        return ImageQuality.fetchValue(tx: tx)
    }
}

// MARK: - OWS2FAManager

protocol _MessageBackup_OWS2FAManagerShim {
    func getPin(tx: DBReadTransaction) -> String?
    func restorePinFromBackup(_ pin: String, tx: DBWriteTransaction)
    func areRemindersEnabled(tx: DBReadTransaction) -> Bool
    func setAreRemindersEnabled(_ areRemindersEnabled: Bool, tx: DBWriteTransaction)
    func recordReminderCompleted(
        repetitionIntervalAdjustment: OWS2FAManager.PinReminderRepetitionIntervalAdjustment?,
        tx: DBWriteTransaction,
    )
}

class _MessageBackup_OWS2FAManagerWrapper: _MessageBackup_OWS2FAManagerShim {
    private let ows2FAManager: OWS2FAManager

    init(_ ows2FAManager: OWS2FAManager) {
        self.ows2FAManager = ows2FAManager
    }

    func getPin(tx: DBReadTransaction) -> String? {
        ows2FAManager.pinCode(transaction: tx)
    }

    func restorePinFromBackup(_ pin: String, tx: DBWriteTransaction) {
        ows2FAManager.restorePinFromBackup(pin, transaction: tx)
    }

    func areRemindersEnabled(tx: DBReadTransaction) -> Bool {
        ows2FAManager.areRemindersEnabled(transaction: tx)
    }

    func setAreRemindersEnabled(_ areRemindersEnabled: Bool, tx: DBWriteTransaction) {
        ows2FAManager.setAreRemindersEnabled(areRemindersEnabled, transaction: tx)
    }

    func recordReminderCompleted(
        repetitionIntervalAdjustment: OWS2FAManager.PinReminderRepetitionIntervalAdjustment?,
        tx: DBWriteTransaction,
    ) {
        ows2FAManager.recordReminderCompleted(
            repetitionIntervalAdjustment: repetitionIntervalAdjustment,
            tx: tx,
        )
    }
}

// MARK: - Preferences

protocol _MessageBackup_PreferencesShim {
    func shouldShowUnidentifiedDeliveryIndicators(tx: DBReadTransaction) -> Bool
    func setShouldShowUnidentifiedDeliveryIndicators(value: Bool, tx: DBWriteTransaction)
    func isSystemCallLogEnabled(tx: DBReadTransaction) -> Bool?
    func setIsSystemCallLogEnabled(_ value: Bool, tx: DBWriteTransaction)
}

class _MessageBackup_PreferencesWrapper: _MessageBackup_PreferencesShim {
    let preferences: Preferences
    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func shouldShowUnidentifiedDeliveryIndicators(tx: DBReadTransaction) -> Bool {
        preferences.shouldShowUnidentifiedDeliveryIndicators(transaction: tx)
    }

    func setShouldShowUnidentifiedDeliveryIndicators(value: Bool, tx: DBWriteTransaction) {
        preferences.setShouldShowUnidentifiedDeliveryIndicators(value, transaction: tx)
    }

    func isSystemCallLogEnabled(tx: DBReadTransaction) -> Bool? {
        preferences.isSystemCallLogEnabled(tx: tx)
    }

    func setIsSystemCallLogEnabled(_ value: Bool, tx: DBWriteTransaction) {
        preferences.setIsSystemCallLogEnabled(value, tx: tx)
    }
}

// MARK: - ProfileManager

protocol _MessageBackup_ProfileManagerShim {

    func enumerateUserProfiles(
        tx: DBReadTransaction,
        block: (OWSUserProfile) throws(CancellationError) -> Bool,
    ) throws(CancellationError) -> Void

    func getUserProfile(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSUserProfile?

    func getUserProfileForLocalUser(tx: DBReadTransaction) -> OWSUserProfile?

    func isGroupId(inProfileWhitelist groupId: Data, tx: DBReadTransaction) -> Bool

    func addRecipientToProfileWhitelist(_ recipient: inout SignalRecipient, tx: DBWriteTransaction)

    func addGroupToWhitelist(_ groupRecord: inout GroupRecord, tx: DBWriteTransaction)

    func insertLocalUserProfile(
        givenName: String,
        familyName: String?,
        avatarUrlPath: String?,
        bio: String?,
        bioEmoji: String?,
        profileKey: Aes256Key,
        tx: DBWriteTransaction,
    )

    func upsertOtherUserProfile(
        insertableAddress: OWSUserProfile.InsertableAddress,
        givenName: String?,
        familyName: String?,
        profileKey: Aes256Key?,
        tx: DBWriteTransaction,
    )
}

class _MessageBackup_ProfileManagerWrapper: _MessageBackup_ProfileManagerShim {
    private let profileManager: ProfileManager

    init(_ profileManager: ProfileManager) {
        self.profileManager = profileManager
    }

    func enumerateUserProfiles(
        tx: DBReadTransaction,
        block: (OWSUserProfile) throws(CancellationError) -> Bool,
    ) throws(CancellationError) {
        var cursor = FailIfThrowsRecordCursor {
            try OWSUserProfile.fetchCursor(tx.database)
        }

        while let profile = cursor.next(), try block(profile) {}
    }

    func getUserProfile(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSUserProfile? {
        profileManager.userProfile(for: address, tx: tx)
    }

    func getUserProfileForLocalUser(tx: DBReadTransaction) -> OWSUserProfile? {
        return OWSUserProfile.getUserProfileForLocalUser(tx: tx)
    }

    func isGroupId(inProfileWhitelist groupId: Data, tx: DBReadTransaction) -> Bool {
        profileManager.isGroupId(inProfileWhitelist: groupId, transaction: tx)
    }

    func addRecipientToProfileWhitelist(_ recipient: inout SignalRecipient, tx: DBWriteTransaction) {
        profileManager.addRecipientToProfileWhitelist(
            &recipient,
            userProfileWriter: .backupRestore,
            tx: tx,
        )
    }

    func addGroupToWhitelist(_ groupRecord: inout GroupRecord, tx: DBWriteTransaction) {
        profileManager.addGroupToProfileWhitelist(
            &groupRecord,
            userProfileWriter: .backupRestore,
            tx: tx,
        )
    }

    func insertLocalUserProfile(
        givenName: String,
        familyName: String?,
        avatarUrlPath: String?,
        bio: String?,
        bioEmoji: String?,
        profileKey: Aes256Key,
        tx: DBWriteTransaction,
    ) {
        /// We can't simply insert a local-user profile here, because
        /// `OWSProfileManager` will create one itself during its `warmCaches`
        /// initialization dance. So, we'll grab the one that was created and
        /// simply overwrite its fields.
        let localUserProfile = OWSUserProfile.getOrBuildUserProfileForLocalUser(
            userProfileWriter: .backupRestore,
            tx: tx,
        )

        localUserProfile.upsertWithNoSideEffects(
            givenName: givenName,
            familyName: familyName,
            avatarUrlPath: avatarUrlPath,
            bio: bio,
            bioEmoji: bioEmoji,
            profileKey: profileKey,
            tx: tx,
        )
    }

    func upsertOtherUserProfile(
        insertableAddress: OWSUserProfile.InsertableAddress,
        givenName: String?,
        familyName: String?,
        profileKey: Aes256Key?,
        tx: DBWriteTransaction,
    ) {
        if case .localUser = insertableAddress {
            owsFailDebug("Cannot use this method for the local user's profile!")
            return
        }
        /// We can't simply insert a profile here, because we might have created
        /// a profile through another flow (e.g., by setting a "missing" profile
        /// key).
        let profile = OWSUserProfile.getOrBuildUserProfile(
            for: insertableAddress,
            userProfileWriter: .backupRestore,
            tx: tx,
        )

        profile.upsertWithNoSideEffects(
            givenName: givenName,
            familyName: familyName,
            avatarUrlPath: nil,
            bio: nil,
            bioEmoji: nil,
            profileKey: profileKey,
            tx: tx,
        )
    }
}

// MARK: - ReactionManager

protocol _MessageBackup_ReactionManagerShim {
    func customEmojiSet(tx: DBReadTransaction) -> [String]?
    func setCustomEmojiSet(emojis: [String]?, tx: DBWriteTransaction)
}

class _MessageBackup_ReactionManagerWrapper: _MessageBackup_ReactionManagerShim {
    func customEmojiSet(tx: DBReadTransaction) -> [String]? {
        ReactionManager.customEmojiSet(transaction: tx)
    }

    func setCustomEmojiSet(emojis: [String]?, tx: DBWriteTransaction) {
        ReactionManager.setCustomEmojiSet(emojis, transaction: tx)
    }
}

// MARK: - ReceiptManager

protocol _MessageBackup_ReceiptManagerShim {
    func areReadReceiptsEnabled(tx: DBReadTransaction) -> Bool
    func setAreReadReceiptsEnabled(value: Bool, tx: DBWriteTransaction)
}

class _MessageBackup_ReceiptManagerWrapper: _MessageBackup_ReceiptManagerShim {
    let receiptManager: OWSReceiptManager
    init(receiptManager: OWSReceiptManager) {
        self.receiptManager = receiptManager
    }

    func areReadReceiptsEnabled(tx: DBReadTransaction) -> Bool {
        OWSReceiptManager.areReadReceiptsEnabled(transaction: tx)
    }

    func setAreReadReceiptsEnabled(value: Bool, tx: DBWriteTransaction) {
        receiptManager.setAreReadReceiptsEnabled(value, transaction: tx)
    }
}

// MARK: - ScreenLock

protocol _MessageBackup_ScreenLockShim {
    func isScreenLockEnabled(tx: DBReadTransaction) -> Bool
    func setIsScreenLockEnabled(_ value: Bool, tx: DBWriteTransaction)
    func screenLockTimeout(tx: DBReadTransaction) -> TimeInterval
    func setScreenLockTimeout(_ timeout: TimeInterval, tx: DBWriteTransaction)
}

class _MessageBackup_ScreenLockWrapper: _MessageBackup_ScreenLockShim {
    func isScreenLockEnabled(tx: DBReadTransaction) -> Bool {
        return ScreenLock.shared.isScreenLockEnabled(tx: tx)
    }

    func setIsScreenLockEnabled(_ value: Bool, tx: DBWriteTransaction) {
        ScreenLock.shared.setIsScreenLockEnabled(value, tx: tx)
    }

    func screenLockTimeout(tx: DBReadTransaction) -> TimeInterval {
        return ScreenLock.shared.screenLockTimeout(tx: tx)
    }

    func setScreenLockTimeout(_ timeout: TimeInterval, tx: DBWriteTransaction) {
        ScreenLock.shared.setScreenLockTimeout(timeout, tx: tx)
    }
}

// MARK: - SSKPreferences

protocol _MessageBackup_SSKPreferencesShim {
    func preferContactAvatars(tx: DBReadTransaction) -> Bool
    func setPreferContactAvatars(value: Bool, tx: DBWriteTransaction)

    func shouldKeepMutedChatsArchived(tx: DBReadTransaction) -> Bool
    func setShouldKeepMutedChatsArchived(value: Bool, tx: DBWriteTransaction)
    func setHasSavedThread(_ newValue: Bool, tx: DBWriteTransaction)
}

class _MessageBackup_SSKPreferencesWrapper: _MessageBackup_SSKPreferencesShim {
    func preferContactAvatars(tx: DBReadTransaction) -> Bool {
        SSKPreferences.preferContactAvatars(transaction: tx)
    }

    func setPreferContactAvatars(value: Bool, tx: DBWriteTransaction) {
        SSKPreferences.setPreferContactAvatars(value, updateStorageService: false, transaction: tx)
    }

    func shouldKeepMutedChatsArchived(tx: DBReadTransaction) -> Bool {
        SSKPreferences.shouldKeepMutedChatsArchived(transaction: tx)
    }

    func setShouldKeepMutedChatsArchived(value: Bool, tx: DBWriteTransaction) {
        SSKPreferences.setShouldKeepMutedChatsArchived(value, transaction: tx)
    }

    func setHasSavedThread(_ newValue: Bool, tx: DBWriteTransaction) {
        SSKPreferences.setHasSavedThread(newValue, transaction: tx)
    }
}

// MARK: - StoryManager

protocol _MessageBackup_StoryManagerShim {
    func hasSetMyStoriesPrivacy(tx: DBReadTransaction) -> Bool
    func setHasSetMyStoriesPrivacy(value: Bool, tx: DBWriteTransaction)
    func areStoriesEnabled(tx: DBReadTransaction) -> Bool
    func setAreStoriesEnabled(value: Bool, tx: DBWriteTransaction)
    func areViewReceiptsEnabled(tx: DBReadTransaction) -> Bool
    func setAreViewReceiptsEnabled(value: Bool, tx: DBWriteTransaction)
}

class _MessageBackup_StoryManagerWrapper: _MessageBackup_StoryManagerShim {
    func hasSetMyStoriesPrivacy(tx: DBReadTransaction) -> Bool {
        StoryManager.hasSetMyStoriesPrivacy(transaction: tx)
    }

    func setHasSetMyStoriesPrivacy(value: Bool, tx: DBWriteTransaction) {
        StoryManager.setHasSetMyStoriesPrivacy(value, shouldUpdateStorageService: false, transaction: tx)
    }

    func areStoriesEnabled(tx: DBReadTransaction) -> Bool {
        StoryManager.areStoriesEnabled(transaction: tx)
    }

    func setAreStoriesEnabled(value: Bool, tx: DBWriteTransaction) {
        StoryManager.setAreStoriesEnabled(value, shouldUpdateStorageService: false, transaction: tx)
    }

    func areViewReceiptsEnabled(tx: DBReadTransaction) -> Bool {
        StoryManager.areViewReceiptsEnabled(transaction: tx)
    }

    func setAreViewReceiptsEnabled(value: Bool, tx: DBWriteTransaction) {
        StoryManager.setAreViewReceiptsEnabled(value, shouldUpdateStorageService: false, transaction: tx)
    }
}

// MARK: - SystemStoryManager

protocol _MessageBackup_SystemStoryManagerShim {
    func isOnboardingStoryViewed(tx: DBReadTransaction) -> Bool
    func setHasViewedOnboardingStory(value: Bool, tx: DBWriteTransaction)
    func hasSeenGroupStoryEducationSheet(tx: DBReadTransaction) -> Bool
    func setHasSeenGroupStoryEducationSheet(value: Bool, tx: DBWriteTransaction)
}

class _MessageBackup_SystemStoryManagerWrapper: _MessageBackup_SystemStoryManagerShim {
    let systemStoryManager: SystemStoryManagerProtocol
    init(systemStoryManager: SystemStoryManagerProtocol) {
        self.systemStoryManager = systemStoryManager
    }

    func isOnboardingStoryViewed(tx: DBReadTransaction) -> Bool {
        systemStoryManager.isOnboardingStoryViewed(transaction: tx)
    }

    func setHasViewedOnboardingStory(value: Bool, tx: DBWriteTransaction) {
        guard value else {
            /// This is a one-way setting, so there's no way to set `false`. If
            /// it's `false`, simply set nothing.
            return
        }

        let source: OnboardingStoryViewSource = .local(
            timestamp: 0,
            shouldUpdateStorageService: false,
        )
        try? systemStoryManager.setHasViewedOnboardingStory(source: source, transaction: tx)
    }

    func hasSeenGroupStoryEducationSheet(tx: DBReadTransaction) -> Bool {
        systemStoryManager.isGroupStoryEducationSheetViewed(tx: tx)
    }

    func setHasSeenGroupStoryEducationSheet(value: Bool, tx: DBWriteTransaction) {
        guard value else {
            /// This is a one-way setting, so there's no way to set `false`. If
            /// it's `false`, simply set nothing.
            return
        }

        systemStoryManager.setGroupStoryEducationSheetViewed(tx: tx)
    }
}

// MARK: - TypingIndicators

protocol _MessageBackup_TypingIndicatorsShim {
    func areTypingIndicatorsEnabled() -> Bool
    func setTypingIndicatorsEnabled(value: Bool, tx: DBWriteTransaction)
}

class _MessageBackup_TypingIndicatorsWrapper: _MessageBackup_TypingIndicatorsShim {
    let typingIndicators: TypingIndicators
    init(typingIndicators: TypingIndicators) {
        self.typingIndicators = typingIndicators
    }

    func areTypingIndicatorsEnabled() -> Bool {
        typingIndicators.areTypingIndicatorsEnabled()
    }

    func setTypingIndicatorsEnabled(value: Bool, tx: DBWriteTransaction) {
        typingIndicators.setTypingIndicatorsEnabled(value: value, transaction: tx)
    }
}

// MARK: - UDManager

protocol _MessageBackup_UDManagerShim {
    func phoneNumberSharingMode(tx: DBReadTransaction) -> PhoneNumberSharingMode?
    func setPhoneNumberSharingMode(mode: PhoneNumberSharingMode, tx: DBWriteTransaction)
    func shouldAllowUnrestrictedAccessLocal(tx: DBReadTransaction) -> Bool
    func setShouldAllowUnrestrictedAccessLocal(_ value: Bool, tx: DBWriteTransaction)
}

class _MessageBackup_UDManagerWrapper: _MessageBackup_UDManagerShim {
    let udManager: OWSUDManager
    init(udManager: OWSUDManager) {
        self.udManager = udManager
    }

    func phoneNumberSharingMode(tx: DBReadTransaction) -> PhoneNumberSharingMode? {
        udManager.phoneNumberSharingMode(tx: tx)
    }

    func setPhoneNumberSharingMode(mode: PhoneNumberSharingMode, tx: DBWriteTransaction) {
        udManager.setPhoneNumberSharingMode(mode, updateStorageServiceAndProfile: false, tx: tx)
    }

    func shouldAllowUnrestrictedAccessLocal(tx: DBReadTransaction) -> Bool {
        udManager.shouldAllowUnrestrictedAccessLocal(transaction: tx)
    }

    func setShouldAllowUnrestrictedAccessLocal(_ value: Bool, tx: DBWriteTransaction) {
        udManager.setShouldAllowUnrestrictedAccessLocal(value, tx: tx)
    }
}
