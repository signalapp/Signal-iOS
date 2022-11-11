//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

/**
 * The users privacy preference for what kind of content to show in lock screen notifications.
 */
typedef NS_CLOSED_ENUM(NSUInteger, NotificationType) {
    NotificationNoNameNoPreview = 0,
    NotificationNameNoPreview = 1,
    NotificationNamePreview = 2,
};

NSString *NSStringForNotificationType(NotificationType value);

// Used when migrating logging to NSUserDefaults.
extern NSString *const OWSPreferencesSignalDatabaseCollection;
extern NSString *const OWSPreferencesKeyEnableDebugLog;
extern NSString *const OWSPreferencesCallLoggingDidChangeNotification;

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;

@interface OWSPreferences : NSObject

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

#pragma mark - Helpers

- (void)removeAllValues;

#pragma mark - Specific Preferences

+ (BOOL)isAudibleErrorLoggingEnabled;
+ (void)setIsAudibleErrorLoggingEnabled:(BOOL)value;

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
- (BOOL)shouldShowUnidentifiedDeliveryIndicatorsWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(shouldShowUnidentifiedDeliveryIndicators(transaction:));
- (void)setShouldShowUnidentifiedDeliveryIndicatorsAndSendSyncMessage:(BOOL)value;
- (void)setShouldShowUnidentifiedDeliveryIndicators:(BOOL)value transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)shouldNotifyOfNewAccountsWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(shouldNotifyOfNewAccounts(transaction:));

- (void)setShouldNotifyOfNewAccounts:(BOOL)newValue
                         transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(shouldNotifyOfNewAccounts(_:transaction:));

@property (nonatomic, readonly) CGFloat cachedDeviceScale;

- (BOOL)wasViewOnceTooltipShown;
- (void)setWasViewOnceTooltipShown;

- (BOOL)wasGroupCallTooltipShown;
- (void)incrementGroupCallTooltipShownCount;
- (void)setWasGroupCallTooltipShown;

- (BOOL)wasBlurTooltipShown;
- (void)setWasBlurTooltipShown;

- (BOOL)wasDeleteForEveryoneConfirmationShown;
- (void)setWasDeleteForEveryoneConfirmationShown;

#pragma mark Callkit

- (BOOL)isSystemCallLogEnabled;
- (void)setIsSystemCallLogEnabled:(BOOL)value;

#pragma mark direct call connectivity (non-TURN)

- (BOOL)doCallsHideIPAddress;
- (void)setDoCallsHideIPAddress:(BOOL)value;

#pragma mark - Push Tokens

- (void)setPushToken:(NSString *)value;
- (nullable NSString *)getPushToken;

- (void)setVoipToken:(nullable NSString *)value;
- (nullable NSString *)getVoipToken;

- (void)unsetRecordedAPNSTokens;

@end

NS_ASSUME_NONNULL_END
