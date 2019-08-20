//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

/**
 * The users privacy preference for what kind of content to show in lock screen notifications.
 */
typedef NS_CLOSED_ENUM(NSUInteger, NotificationType){
    NotificationNoNameNoPreview,
    NotificationNameNoPreview,
    NotificationNamePreview,
};

NSString *NSStringForNotificationType(NotificationType value);

// Used when migrating logging to NSUserDefaults.
extern NSString *const OWSPreferencesSignalDatabaseCollection;
extern NSString *const OWSPreferencesKeyEnableDebugLog;
extern NSString *const OWSPreferencesCallLoggingDidChangeNotification;

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class YapDatabaseReadWriteTransaction;

@interface OWSPreferences : NSObject

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

#pragma mark - Helpers

- (void)removeAllValues;

#pragma mark - Specific Preferences

+ (BOOL)isReadyForAppExtensions;

+ (BOOL)isYdbReadyForAppExtensions;
+ (void)setIsYdbReadyForAppExtensions;

+ (BOOL)isGrdbReadyForAppExtensions;
+ (void)setIsGrdbReadyForAppExtensions;

+ (BOOL)isLoggingEnabled;
+ (void)setIsLoggingEnabled:(BOOL)value;

- (BOOL)screenSecurityIsEnabled;
- (void)setScreenSecurity:(BOOL)value;

- (NotificationType)notificationPreviewType;
- (void)setNotificationPreviewType:(NotificationType)type;
- (NSString *)nameForNotificationPreviewType:(NotificationType)notificationType;

- (BOOL)soundInForeground;
- (void)setSoundInForeground:(BOOL)value;

- (BOOL)hasDeclinedNoContactsView;
- (void)setHasDeclinedNoContactsView:(BOOL)value;

- (void)setIOSUpgradeNagDate:(NSDate *)value;
- (nullable NSDate *)iOSUpgradeNagDate;

- (BOOL)hasGeneratedThumbnails;
- (void)setHasGeneratedThumbnails:(BOOL)value;

- (BOOL)shouldShowUnidentifiedDeliveryIndicators;
- (void)setShouldShowUnidentifiedDeliveryIndicators:(BOOL)value;

- (BOOL)shouldNotifyOfNewAccountsWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(shouldNotifyOfNewAccounts(transaction:));

- (void)setShouldNotifyOfNewAccounts:(BOOL)newValue
                         transaction:(SDSAnyWriteTransaction *)transactio
    NS_SWIFT_NAME(shouldNotifyOfNewAccounts(_:transaction:));

- (BOOL)isViewOnceMessagesEnabled;
- (void)setIsViewOnceMessagesEnabled:(BOOL)value;

#pragma mark Callkit

- (BOOL)isSystemCallLogEnabled;
- (void)setIsSystemCallLogEnabled:(BOOL)value;

#pragma mark - Legacy CallKit settings

- (void)applyCallLoggingSettingsForLegacyUsersWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

- (BOOL)isCallKitEnabled;
- (void)setIsCallKitEnabled:(BOOL)value;

// Returns YES IFF isCallKitEnabled has been set by user.
- (BOOL)isCallKitEnabledSet;

- (BOOL)isCallKitPrivacyEnabled;
- (void)setIsCallKitPrivacyEnabled:(BOOL)value;
// Returns YES IFF isCallKitPrivacyEnabled has been set by user.
- (BOOL)isCallKitPrivacySet;

#pragma mark direct call connectivity (non-TURN)

- (BOOL)doCallsHideIPAddress;
- (void)setDoCallsHideIPAddress:(BOOL)value;

#pragma mark - Push Tokens

- (void)setPushToken:(NSString *)value;
- (nullable NSString *)getPushToken;

- (void)setVoipToken:(NSString *)value;
- (nullable NSString *)getVoipToken;

- (void)unsetRecordedAPNSTokens;

@end

NS_ASSUME_NONNULL_END
